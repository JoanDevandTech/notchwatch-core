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

/// Interruptor para simular caídas de una colección.
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

/// Fuente falsa: sirve listas fijas por colección y puede fallar bajo demanda.
final class FakeSource: IncidentSource, @unchecked Sendable {
    let id: String
    let kind: SourceKind = .asana
    let displayName: String
    let collections: [WatchedCollection]
    let capabilities: SourceCapabilities = [.assignToMe, .dueDate]

    private let lock = NSLock()
    private var incidentsByCollection: [String: [Incident]]
    private var failures: [String: SourceError] = [:]
    private(set) var performed: [(IncidentAction, Incident)] = []

    init(id: String, collections: [WatchedCollection], incidents: [String: [Incident]] = [:]) {
        self.id = id
        self.displayName = id
        self.collections = collections
        self.incidentsByCollection = incidents
    }

    func setIncidents(_ incidents: [Incident], for collectionID: String) {
        lock.lock()
        defer { lock.unlock() }
        incidentsByCollection[collectionID] = incidents
    }

    func setFailure(_ error: SourceError?, for collectionID: String) {
        lock.lock()
        defer { lock.unlock() }
        failures[collectionID] = error
    }

    func identity() async throws -> SourceIdentity {
        SourceIdentity(userID: "u-\(id)", name: "Usuario \(id)")
    }

    func openIncidents(in collection: WatchedCollection) async throws -> [Incident] {
        try withLock {
            if let error = failures[collection.id] {
                throw error
            }
            return incidentsByCollection[collection.id] ?? []
        }
    }

    func perform(_ action: IncidentAction, on incident: Incident) async throws {
        withLock { performed.append((action, incident)) }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
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

/// Identificador de colección del preajuste de Tubuencamino para una clave.
func tbcCollectionID(_ key: String) -> String {
    WatchedCollection.makeID(sourceID: AsanaPresets.tubuencaminoSourceID, key: key)
}

/// Nombre corto de la colección del preajuste; la clave misma si no existe.
func tbcCollectionName(_ key: String) -> String {
    AsanaPresets.tubuencamino.projects.first(where: { $0.collection.id == tbcCollectionID(key) })?.collection.name ?? key
}

/// Incidencia de prueba en una colección del preajuste de Tubuencamino.
func sampleIncident(
    _ id: String,
    priority: IncidentPriority = .media,
    createdAt: Date,
    collectionKey: String = "ventas"
) -> Incident {
    Incident(
        id: id,
        collectionID: tbcCollectionID(collectionKey),
        collectionName: tbcCollectionName(collectionKey),
        name: "Incidencia \(id)",
        priority: priority,
        createdAt: createdAt
    )
}

/// Proyecto del preajuste por clave.
func presetProject(_ key: String) throws -> AsanaProjectConfig {
    try XCTUnwrap(
        AsanaPresets.tubuencamino.projects.first(where: { $0.collection.id == tbcCollectionID(key) }),
        "Proyecto desconocido: \(key)"
    )
}

/// Preajuste con solo los proyectos indicados activos.
func presetConfig(enabling keys: Set<String>) -> AsanaSourceConfig {
    var config = AsanaPresets.tubuencamino
    for index in config.projects.indices {
        let key = config.projects[index].collection.id.split(separator: "/").last.map(String.init) ?? ""
        config.projects[index].collection.enabled = keys.contains(key)
    }
    return config
}

/// Fuente Asana sobre el preajuste con el transporte indicado.
func presetSource(enabling keys: Set<String>, token: String = "tok", transport: HTTPTransport) -> AsanaSource {
    AsanaSource(config: presetConfig(enabling: keys), token: token, transport: transport)
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
