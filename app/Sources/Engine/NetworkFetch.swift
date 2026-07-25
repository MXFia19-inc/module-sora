import Foundation

/// Réponse brute d'une requête `fetchv2`.
struct FetchResponse {
    let status: Int
    let headers: [String: String]
    let body: Data
    let finalURL: String
}

/// Effectue la requête HTTP native derrière `fetchv2`.
/// Un délégué par requête permet de désactiver le suivi des redirections
/// (utile pour certains résolveurs de flux qui lisent l'en-tête `Location`).
final class NetworkFetch: NSObject, URLSessionTaskDelegate {
    private let followRedirects: Bool

    private init(followRedirects: Bool) {
        self.followRedirects = followRedirects
    }

    static func perform(
        url: URL,
        headers: [String: String],
        method: String,
        body: String?,
        followRedirects: Bool
    ) async throws -> FetchResponse {
        let delegate = NetworkFetch(followRedirects: followRedirects)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body, !body.isEmpty, method.uppercased() != "GET", method.uppercased() != "HEAD" {
            request.httpBody = body.data(using: .utf8)
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        var headerDict: [String: String] = [:]
        http?.allHeaderFields.forEach { key, value in
            if let k = key as? String, let v = value as? String { headerDict[k] = v }
        }
        return FetchResponse(
            status: http?.statusCode ?? 0,
            headers: headerDict,
            body: data,
            finalURL: (http?.url ?? url).absoluteString
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(followRedirects ? request : nil)
    }
}

/// Résultat d'une sonde de lien de flux.
struct ProbeResult {
    let status: Int
    let contentType: String?
    let error: String?
    let ms: Int

    var isOK: Bool { (200...299).contains(status) }

    /// Diagnostic court et lisible.
    var diagnosis: String {
        if let error { return error }
        switch status {
        case 200, 206: return "OK"
        case 401, 403: return "\(status) (headers?)"
        case 404, 410: return "\(status) (dead)"
        case 429: return "429 (rate limited)"
        case 500...599: return "\(status) (server error)"
        default: return "\(status)"
        }
    }
}

extension NetworkFetch {
    /// Sonde un lien de flux : envoie une requête, lit le statut et les en-têtes
    /// de réponse, puis annule avant de télécharger le corps.
    static func probe(url: URL, headers: [String: String], timeout: TimeInterval = 15) async -> ProbeResult {
        let started = Date()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        // N'obtenir que le début : évite de télécharger la vidéo entière.
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")

        do {
            let (bytes, response) = try await session.bytes(for: request)
            bytes.task.cancel() // on ne veut que les en-têtes
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let http = response as? HTTPURLResponse
            return ProbeResult(
                status: http?.statusCode ?? 0,
                contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                error: nil,
                ms: ms
            )
        } catch {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            return ProbeResult(status: 0, contentType: nil,
                               error: (error as NSError).localizedDescription, ms: ms)
        }
    }
}
