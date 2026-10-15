import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstracción del transporte HTTP (permite inyectar un mock en tests).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Transporte real basado en `URLSession`.
public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    // URLSession es thread-safe; @unchecked por si el SDK no lo marca Sendable.
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AsanaError.http(0, "Respuesta no HTTP")
        }
        return (data, http)
    }
}
