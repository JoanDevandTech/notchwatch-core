import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NotchwatchCore

// MARK: - Transporte simulado

/// Respuesta simulada de Asana.
struct MockResponse: Sendable {
    var status: Int
    var body: Data
    var headers: [String: String]

    init(status: Int = 200, body: Data = Data(#"{"data":{}}"#.utf8), headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }
}

enum TestSupportError: Error {
    case missingFixture(String)
    case invalidResponse
}

/// Transporte falso: registra cada request y responde con `handler`.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> MockResponse

    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Requests recibidas, en orden.
    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        let mock = try handler(request)
        guard
            let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: mock.status,
                httpVersion: "HTTP/1.1",
                headerFields: mock.headers
            )
        else {
            throw TestSupportError.invalidResponse
        }
        return (mock.body, response)
    }

    private func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
    }
}

// MARK: - Dobles controlables (thread-safe)

/// Reloj controlable desde el test.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ date: Date) {
        value = date
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

/// Interruptor para simular caídas de un proyecto.
final class FailSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ isOn: Bool = false) {
        value = isOn
    }

    var isOn: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

// MARK: - Fixtures y requests

/// Carga un fixture JSON del bundle de tests (`.process` puede aplanar o no la carpeta).
func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json")
        ?? Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    guard let url else { throw TestSupportError.missingFixture(name) }
    return try Data(contentsOf: url)
}

/// Valor (ya decodificado) de un parámetro de query de la request.
func queryValue(_ request: URLRequest, _ name: String) -> String? {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    return components.queryItems?.first(where: { $0.name == name })?.value
}

/// Cuerpo de la request como texto.
func bodyString(_ request: URLRequest) -> String? {
    request.httpBody.map { String(decoding: $0, as: UTF8.self) }
}

/// Cuerpo JSON de la request como diccionario (comprobación estructural).
func jsonObject(_ request: URLRequest) throws -> [String: Any] {
    let data = try XCTUnwrap(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any])
}

// MARK: - Datos de prueba

/// Fecha fija a partir de ISO8601 sin fracciones ("2026-10-14T08:20:00Z").
func isoDate(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: string) else {
        preconditionFailure("Fecha de test inválida: \(string)")
    }
    return date
}

/// Incidencia de prueba.
func sampleIncident(
    _ gid: String,
    priority: IncidentPriority = .media,
    createdAt: Date,
    projectKey: String = "ventas"
) -> Incident {
    Incident(
        gid: gid,
        projectKey: projectKey,
        projectName: "Ventas Incidencias",
        name: "Incidencia \(gid)",
        priority: priority,
        createdAt: createdAt
    )
}

/// Proyecto de la config por defecto por clave.
func defaultProject(_ key: String) throws -> WatchedProject {
    try XCTUnwrap(
        NotchwatchConfig.tubuencamino.projects.first(where: { $0.key == key }),
        "Proyecto desconocido: \(key)"
    )
}

/// Config por defecto con solo los proyectos indicados activos.
func defaultConfig(enabling keys: Set<String>) -> NotchwatchConfig {
    var config = NotchwatchConfig.tubuencamino
    for index in config.projects.indices {
        config.projects[index].enabled = keys.contains(config.projects[index].key)
    }
    return config
}

// MARK: - Ficheros temporales

/// Carpeta temporal única para un test; el test la borra con `defer`.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("notchwatch-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Lee el estado persistido por el monitor.
func loadStore(at url: URL) throws -> SeenStore {
    let data = try Data(contentsOf: url)
    return try SeenStore.makeDecoder().decode(SeenStore.self, from: data)
}
