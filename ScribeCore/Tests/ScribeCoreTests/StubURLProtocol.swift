import Foundation
import Synchronization

/// Serves canned responses to a `URLSession`. Each stub gets its own host so tests can run in parallel.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case response(status: Int, body: Data)
        case failure(URLError.Code)
        /// Never answers, so the request can only end by being cancelled.
        case hang
    }

    typealias Handler = @Sendable (URLRequest) -> Reply

    private static let handlers = Mutex<[String: Handler]>([:])
    private static let requests = Mutex<[String: [URLRequest]]>([:])

    /// A session and base URL whose requests are answered by `handler`.
    static func stub(_ handler: @escaping Handler) -> (session: URLSession, baseURL: URL) {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        handlers.withLock { $0[host] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return (URLSession(configuration: configuration), URL(string: "http://\(host)")!)
    }

    static func requests(to baseURL: URL) -> [URLRequest] {
        requests.withLock { $0[baseURL.host() ?? ""] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            recorded.httpBody = Self.read(stream)
        }
        Self.requests.withLock { $0[host, default: []].append(recorded) }
        guard let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        switch handler(recorded) {
        case .response(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .hang:
            break
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

extension URLRequest {
    var jsonBody: [String: Any]? {
        httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}
