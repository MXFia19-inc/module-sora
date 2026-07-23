import Foundation
import JavaScriptCore

enum JSEngineError: LocalizedError {
    case contextUnavailable
    case scriptException(String)
    case missingFunction(String)
    case jsError(String)
    case timeout(String, Double)

    var errorDescription: String? {
        switch self {
        case .contextUnavailable: return "Contexte JavaScript indisponible."
        case .scriptException(let m): return "Erreur à l'évaluation du script : \(m)"
        case .missingFunction(let f): return "Fonction « \(f) » absente du module."
        case .jsError(let m): return "Erreur JS : \(m)"
        case .timeout(let f, let s): return "Délai dépassé (\(Int(s))s) pour « \(f) »."
        }
    }
}

/// Drapeau de libération partagé entre le moteur et ses blocs natifs
/// (timers, fetch) sans créer de cycle de rétention avec le contexte.
private final class DisposeFlag {
    var value = false
}

/// Garde-fou pour ne reprendre une continuation qu'une seule fois.
private final class ResumeGuard {
    private var done = false
    private let lock = NSLock()
    func tryResume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Exécute le script d'un module dans un `JSContext` isolé et appelle ses
/// fonctions globales (async) en résolvant les Promises côté Swift.
///
/// IMPORTANT : tout l'accès au `JSContext` se fait sur une **file série dédiée**
/// (`queue`), jamais sur le thread principal — l'UI reste fluide même quand un
/// module lance des dizaines de requêtes (ex. le résolveur de movix).
final class JSEngine {
    private let context: JSContext
    private let moduleName: String
    private weak var debugLog: DebugLog?
    private let settings: AppSettings
    private let queue: DispatchQueue
    private let disposeFlag = DisposeFlag()
    /// Dernière exception remontée par le gestionnaire (pour détecter les
    /// erreurs d'évaluation que le handler « consomme »).
    private var lastException: String?

    private var timeout: Double { max(1, settings.jsTimeout) }

    init(moduleName: String, debugLog: DebugLog, settings: AppSettings) throws {
        guard let ctx = JSContext() else { throw JSEngineError.contextUnavailable }
        self.context = ctx
        self.moduleName = moduleName
        self.debugLog = debugLog
        self.settings = settings
        self.queue = DispatchQueue(label: "moduletester.jsengine.\(moduleName)")
        installNativeBridge()
    }

    // MARK: - Chargement

    /// Injecte les polyfills puis évalue le script du module (sur la file dédiée).
    func evaluate(script: String) throws {
        try queue.sync {
            context.exceptionHandler = { [weak self] _, exception in
                let msg = exception?.toString() ?? "exception JS"
                self?.lastException = msg
                self?.log(.error, msg)
            }
            context.evaluateScript(JSPolyfills.source)
            // Réinitialise juste avant le script du module pour ne capturer que ses erreurs.
            lastException = nil
            context.evaluateScript(script)
            // Le handler « consomme » l'exception (context.exception devient nil),
            // donc on lit aussi lastException pour détecter les erreurs de syntaxe.
            if let ex = context.exception?.toString() ?? lastException {
                context.exception = nil
                throw JSEngineError.scriptException(ex)
            }
        }
    }

    // MARK: - Appel de fonction async

    /// Appelle `fn(args…)` et renvoie la chaîne retournée (résout la Promise, avec timeout).
    func callAsync(_ fn: String, _ args: [Any]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let function = context.objectForKeyedSubscript(fn), !function.isUndefined else {
                    continuation.resume(throwing: JSEngineError.missingFunction(fn)); return
                }
                log(.info, "→ \(fn)(\(args.map { "\($0)" }.joined(separator: ", ")))")

                guard let result = function.call(withArguments: args) else {
                    continuation.resume(throwing: JSEngineError.jsError("l'appel de \(fn) n'a rien retourné")); return
                }
                if let ex = context.exception {
                    let msg = ex.toString() ?? "exception"
                    context.exception = nil
                    continuation.resume(throwing: JSEngineError.jsError(msg)); return
                }

                // Retour synchrone (non-Promise).
                if !result.hasProperty("then") {
                    continuation.resume(returning: Self.stringify(result)); return
                }

                let guardBox = ResumeGuard()
                let timeoutItem = DispatchWorkItem {
                    guard guardBox.tryResume() else { return }
                    continuation.resume(throwing: JSEngineError.timeout(fn, self.timeout))
                }
                queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

                let onResolve: @convention(block) (JSValue?) -> Void = { value in
                    guard guardBox.tryResume() else { return }
                    timeoutItem.cancel()
                    continuation.resume(returning: Self.stringify(value))
                }
                let onReject: @convention(block) (JSValue?) -> Void = { [weak self] err in
                    guard guardBox.tryResume() else { return }
                    timeoutItem.cancel()
                    let msg = err?.toString() ?? "promesse rejetée"
                    self?.log(.error, "\(fn) rejeté : \(msg)")
                    continuation.resume(throwing: JSEngineError.jsError(msg))
                }

                let resolveVal = JSValue(object: onResolve, in: context)
                let rejectVal = JSValue(object: onReject, in: context)
                result.invokeMethod("then", withArguments: [resolveVal as Any, rejectVal as Any])
            }
        }
    }

    private static func stringify(_ value: JSValue?) -> String {
        guard let value, !value.isUndefined, !value.isNull else { return "" }
        return value.toString() ?? ""
    }

    /// Journalise vers le buffer de debug (toujours sur le main).
    private func log(_ kind: LogKind, _ message: String, detail: String? = nil) {
        let module = moduleName
        let dl = debugLog
        DispatchQueue.main.async {
            dl?.append(kind, message, module: module, detail: detail)
        }
    }

    // MARK: - Bridge natif

    /// Coupe l'activité de fond du module : les timers et fetch en cours
    /// n'exécutent plus rien côté JS. À appeler quand le module n'est plus utilisé.
    func dispose() {
        queue.async { [disposeFlag, context] in
            disposeFlag.value = true
            context.exceptionHandler = nil
        }
    }

    private func installNativeBridge() {
        let engineQueue = queue
        let disposeFlag = self.disposeFlag

        // console
        let logBlock: @convention(block) (String, String) -> Void = { [weak self] level, msg in
            self?.log(level == "error" ? .error : .console, msg)
        }
        context.setObject(logBlock, forKeyedSubscript: "__log" as NSString)

        // atob / btoa (chaînes latin1 <-> base64)
        let atobBlock: @convention(block) (String) -> String = { input in
            let padded = Self.padBase64(input)
            guard let data = Data(base64Encoded: padded) else { return "" }
            return String(data: data, encoding: .isoLatin1) ?? ""
        }
        let btoaBlock: @convention(block) (String) -> String = { input in
            let data = input.data(using: .isoLatin1) ?? Data(input.utf8)
            return data.base64EncodedString()
        }
        context.setObject(atobBlock, forKeyedSubscript: "atob" as NSString)
        context.setObject(btoaBlock, forKeyedSubscript: "btoa" as NSString)

        // setTimeout : replanifié sur la file du moteur (accès contexte sûr)
        let setTimeoutBlock: @convention(block) (JSValue, Double) -> Void = { cb, ms in
            let delay = (ms.isFinite && ms > 0) ? ms : 0
            engineQueue.asyncAfter(deadline: .now() + delay / 1000.0) {
                guard !disposeFlag.value else { return }
                cb.call(withArguments: [])
            }
        }
        context.setObject(setTimeoutBlock, forKeyedSubscript: "__setTimeout" as NSString)

        installFetchBridge()
    }

    private func installFetchBridge() {
        let moduleName = self.moduleName
        weak var debugLog = self.debugLog
        let settings = self.settings
        let engineQueue = queue
        let disposeFlag = self.disposeFlag

        func logFetch(_ kind: LogKind, _ msg: String, _ detail: String? = nil) {
            DispatchQueue.main.async { debugLog?.append(kind, msg, module: moduleName, detail: detail) }
        }

        let fetchBlock: @convention(block) (String, JSValue?, JSValue?, JSValue?, JSValue?, JSValue?) -> JSValue? = {
            urlStr, headersVal, methodVal, bodyVal, redirectVal, _ in
            guard let context = JSContext.current() else { return nil }

            var headers: [String: String] = [:]
            if let dict = headersVal?.toDictionary() {
                for (key, value) in dict { headers["\(key)"] = "\(value)" }
            }
            if !headers.keys.contains(where: { $0.lowercased() == "user-agent" }),
               !settings.defaultUserAgent.isEmpty {
                headers["User-Agent"] = settings.defaultUserAgent
            }
            let method = (methodVal?.isString == true ? methodVal?.toString() : nil) ?? "GET"
            let body: String? = {
                guard let bodyVal, !bodyVal.isNull, !bodyVal.isUndefined else { return nil }
                return bodyVal.toString()
            }()
            let followRedirects = redirectVal.map { !$0.isBoolean || $0.toBool() } ?? true

            let started = Date()
            logFetch(.fetch, "\(method) \(urlStr)")

            // Blocage optionnel des trackers (webhooks Discord).
            if settings.blockWebhooks,
               settings.blockedURLPatterns.contains(where: { urlStr.contains($0) }) {
                logFetch(.info, "bloqué (webhook) : \(urlStr)")
                let obj = JSValue(newObjectIn: context)!
                obj.setValue(204, forProperty: "status")
                obj.setValue([String: String](), forProperty: "headers")
                obj.setValue("", forProperty: "_body")
                obj.setValue(urlStr, forProperty: "url")
                return JSValue(newPromiseResolvedWithResult: obj, in: context)
            }

            guard let url = URL(string: urlStr) else {
                let err = JSValue(object: "URL invalide : \(urlStr)", in: context)
                return JSValue(newPromiseRejectedWithReason: err as Any, in: context)
            }

            return JSValue(newPromiseIn: context) { resolve, reject in
                Task.detached {
                    do {
                        let resp = try await NetworkFetch.perform(
                            url: url, headers: headers, method: method,
                            body: body, followRedirects: followRedirects
                        )
                        let ms = Int(Date().timeIntervalSince(started) * 1000)
                        logFetch(.fetch, "\(resp.status) \(urlStr)", "\(ms) ms · \(resp.body.count) o")
                        let bodyString = String(data: resp.body, encoding: .utf8)
                            ?? String(decoding: resp.body, as: UTF8.self)
                        // Retour sur la file du moteur pour manipuler le contexte JS.
                        engineQueue.async {
                            guard !disposeFlag.value else { return }
                            let obj = JSValue(newObjectIn: context)!
                            obj.setValue(resp.status, forProperty: "status")
                            obj.setValue(resp.headers, forProperty: "headers")
                            obj.setValue(bodyString, forProperty: "_body")
                            obj.setValue(resp.finalURL, forProperty: "url")
                            resolve?.call(withArguments: [obj])
                        }
                    } catch {
                        logFetch(.error, "fetch échoué : \(error.localizedDescription)", urlStr)
                        engineQueue.async {
                            let err = JSValue(object: error.localizedDescription, in: context)
                            reject?.call(withArguments: [err as Any])
                        }
                    }
                }
            }
        }
        context.setObject(fetchBlock, forKeyedSubscript: "__fetchNative" as NSString)
    }

    private static func padBase64(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let rem = out.count % 4
        if rem > 0 { out += String(repeating: "=", count: 4 - rem) }
        return out
    }
}
