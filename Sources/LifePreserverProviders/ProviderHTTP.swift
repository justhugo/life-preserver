import Foundation
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

public enum SubscriptionError: LocalizedError {
    case authentication, renewalRejected, response, denied, busyPort, timeout, rateLimited(Date), status(Int)
    public var errorDescription: String? {
        switch self {
        case .authentication: "Your provider session has expired. Reconnect this account."
        case .renewalRejected: "Your saved provider sign-in has expired or been revoked. Reconnect this account in Settings → Accounts."
        case .response: "The provider didn’t return a readable subscription usage value. Try refreshing shortly."
        case .denied: "Sign-in was not approved. You can reconnect when you’re ready."
        case .busyPort: "The sign-in callback port is busy. Finish any other provider sign-in and try again."
        case .timeout: "Sign-in timed out. Please try again."
        case .rateLimited: "The provider has paused usage checks. Life Preserver will retry after the cooldown."
        case let .status(code): "The provider couldn’t complete the request (HTTP \(code)). Try again shortly."
        }
    }
}

/// Isolated, cache-free transport. Never forward credentials through redirects.
@MainActor
public final class SubscriptionHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public static let shared = SubscriptionHTTP()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    public func request(_ url: URL, bearer: String? = nil, body: Data? = nil,
                 contentType: String = "application/json", headers: [String: String] = [:],
                 refreshingCredential: Bool = false) async throws -> Data {
        precondition(url.scheme == "https")
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("LifePreserver/1.2", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse, data.count <= 4_194_304 else { throw SubscriptionError.response }
        if refreshingCredential, OAuthTokenFailure.requiresReconnect(status: response.statusCode, data: data) {
            throw SubscriptionError.renewalRejected
        }
        if response.statusCode == 401 { throw SubscriptionError.authentication }
        if response.statusCode == 429 {
            let delay = TimeInterval(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 300
            throw SubscriptionError.rateLimited(Date().addingTimeInterval(max(60, min(3600, delay))))
        }
        guard (200..<300).contains(response.statusCode) else { throw SubscriptionError.status(response.statusCode) }
        if let status = response.value(forHTTPHeaderField: "grpc-status"), status != "0" { throw SubscriptionError.authentication }
        return data
    }

}
