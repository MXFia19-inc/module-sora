import Foundation
import WebKit
import UIKit

/// Résout les challenges Cloudflare (« Just a moment… ») en chargeant la page
/// dans un vrai `WKWebView` invisible, puis en récupérant les cookies obtenus
/// (`cf_clearance`) et le User-Agent du moteur web.
///
/// Le cookie de clearance est lié au couple (User-Agent, IP) : les requêtes
/// suivantes doivent donc réutiliser le MÊME User-Agent, d'où sa mémorisation.
@MainActor
final class CloudflareBypass: NSObject {
    static let shared = CloudflareBypass()

    private var webView: WKWebView?
    /// Hôtes résolus récemment (host → date de résolution).
    private var solvedHosts: [String: Date] = [:]
    /// User-Agent du WKWebView, à réutiliser avec le cookie de clearance.
    private(set) var userAgent: String?

    /// Durée de validité d'une résolution avant de retenter.
    private let clearanceTTL: TimeInterval = 30 * 60

    // MARK: - Détection

    /// Reconnaît une page de challenge Cloudflare dans une réponse.
    nonisolated static func looksLikeChallenge(status: Int, body: String) -> Bool {
        // Un vrai contenu est généralement bien plus gros qu'une page de challenge.
        guard body.count < 200_000 else { return false }
        let lower = body.lowercased()
        if lower.contains("just a moment")
            || lower.contains("cf-browser-verification")
            || lower.contains("challenge-platform")
            || lower.contains("checking your browser")
            || lower.contains("cf_chl_opt") {
            return true
        }
        return (status == 403 || status == 503) && lower.contains("cloudflare")
    }

    /// User-Agent à utiliser si l'hôte a déjà été résolu récemment.
    func userAgentIfSolved(host: String?) -> String? {
        guard let host, let date = solvedHosts[host],
              Date().timeIntervalSince(date) < clearanceTTL else { return nil }
        return userAgent
    }

    func isSolved(host: String?) -> Bool {
        userAgentIfSolved(host: host) != nil
    }

    // MARK: - Résolution

    /// Charge l'URL dans le WebView et attend que le challenge disparaisse.
    /// Renvoie `true` si la page a été servie (cookies récupérés).
    func solve(url: URL, timeout: TimeInterval = 25) async -> Bool {
        guard let host = url.host else { return false }
        let web = ensureWebView()

        web.load(URLRequest(url: url))
        if userAgent == nil {
            userAgent = await eval("navigator.userAgent", on: web)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let html = await eval("document.documentElement.outerHTML", on: web),
                  !html.isEmpty else { continue }
            if !Self.looksLikeChallenge(status: 200, body: html) {
                await harvestCookies(from: web)
                if userAgent == nil { userAgent = await eval("navigator.userAgent", on: web) }
                solvedHosts[host] = Date()
                return true
            }
        }
        return false
    }

    /// Oublie les clearances (utile depuis les réglages).
    func reset() {
        solvedHosts.removeAll()
        webView?.removeFromSuperview()
        webView = nil
    }

    // MARK: - Interne

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persistant : garde les cookies
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 640), configuration: config)
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        // Le WebView doit appartenir à une fenêtre pour que le JS du challenge tourne.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first {
            window.insertSubview(web, at: 0)
        }
        webView = web
        return web
    }

    private func eval(_ js: String, on web: WKWebView) async -> String? {
        await withCheckedContinuation { continuation in
            web.evaluateJavaScript(js) { result, _ in
                continuation.resume(returning: result as? String)
            }
        }
    }

    /// Copie les cookies du WebView vers le stockage partagé utilisé par URLSession.
    private func harvestCookies(from web: WKWebView) async {
        let store = web.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
}
