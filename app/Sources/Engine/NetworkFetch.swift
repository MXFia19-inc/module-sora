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
