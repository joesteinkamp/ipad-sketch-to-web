import Foundation

/// A test-only `URLProtocol` that intercepts HTTP requests and replays a queued
/// response. Use it to drive `URLSession`-backed clients (`FigmaMCPClient`,
/// `GeminiClient` extension) without network access.
///
/// Two usage patterns:
///
/// 1. **Custom session** (preferred when the SUT accepts a session):
///    ```
///    let config = URLSessionConfiguration.ephemeral
///    config.protocolClasses = [URLProtocolStub.self]
///    let session = URLSession(configuration: config)
///    URLProtocolStub.queue(response: ..., body: ...)
///    let client = FigmaMCPClient(endpoint: ..., tokenProvider: ..., session: session)
///    ```
///
/// 2. **Global registration** (when the SUT uses `URLSession.shared`):
///    ```
///    URLProtocol.registerClass(URLProtocolStub.self)
///    defer { URLProtocol.unregisterClass(URLProtocolStub.self) }
///    ```
final class URLProtocolStub: URLProtocol {

    /// One scripted response. `error` short-circuits transport; otherwise
    /// `response`/`body` are delivered to the client.
    struct Stub {
        let response: URLResponse
        let body: Data
        let error: Error?
    }

    private static let lock = NSLock()
    private static var queue: [Stub] = []
    private static var capturedRequests: [URLRequest] = []

    /// Queues one stubbed response. Calls are FIFO.
    static func queue(response: URLResponse, body: Data = Data(), error: Error? = nil) {
        lock.lock(); defer { lock.unlock() }
        queue.append(Stub(response: response, body: body, error: error))
    }

    /// Convenience for an HTTP/1.1 response with the given status, headers, and body.
    static func queueHTTP(
        url: URL,
        statusCode: Int,
        headers: [String: String] = [:],
        body: Data = Data()
    ) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        queue(response: response, body: body)
    }

    /// Returns and clears all requests intercepted since the last call.
    static func drainCapturedRequests() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        let captured = capturedRequests
        capturedRequests.removeAll()
        return captured
    }

    /// Clears any queued stubs and captured requests.
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queue.removeAll()
        capturedRequests.removeAll()
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let stub: Stub? = Self.queue.isEmpty ? nil : Self.queue.removeFirst()
        Self.lock.unlock()

        guard let stub = stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        client?.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { /* no-op */ }
}
