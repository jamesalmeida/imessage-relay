import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WebhookError: Error, Equatable, CustomStringConvertible {
    case status(Int)
    case network
    case timeout

    public var description: String {
        switch self {
        case .status(let code):
            return "status=\(code)"
        case .network:
            return "error=network"
        case .timeout:
            return "error=timeout"
        }
    }
}

public protocol WebhookPosting: AnyObject {
    func post(body: Data, url: URL, authorization: String?) throws -> Int
}

public final class URLSessionWebhookClient: WebhookPosting {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        self.session = session ?? URLSessionWebhookClient.makeSession()
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }

    public func post(body: Data, url: URL, authorization: String?) throws -> Int {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("imessage-relay", forHTTPHeaderField: "User-Agent")
        if let authorization, !authorization.isEmpty {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        let task = session.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            if let error = error as? URLError, error.code == .timedOut {
                box.result = .failure(.timeout)
                return
            }
            if error != nil {
                box.result = .failure(.network)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                box.result = .failure(.network)
                return
            }
            box.result = .success(http.statusCode)
        }
        task.resume()
        let wait = semaphore.wait(timeout: .now() + .seconds(20))
        if wait == .timedOut {
            task.cancel()
            throw WebhookError.timeout
        }
        guard let result = box.result else { throw WebhookError.network }
        switch result {
        case .failure(let error):
            throw error
        case .success(let status):
            guard (200..<300).contains(status) else { throw WebhookError.status(status) }
            return status
        }
    }
}

private final class ResultBox {
    var result: Result<Int, WebhookError>?
}
