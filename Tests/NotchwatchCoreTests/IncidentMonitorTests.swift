import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NotchwatchCore

final class IncidentMonitorTests: XCTestCase {
    /// Momento fijo del primer poll: la incidencia 1211000000000001 se creó 4,5 min antes;
    /// el resto de Ventas y las dos de General tienen más de 10 min.
    private let fixedNow = isoDate("2026-10-14T08:20:00Z")

    private let ventasOld: Set<String> = ["1211000000000002", "1211000000000003", "1211000000000004"]
    private let generalIDs: Set<String> = ["1212000000000001", "1212000000000002"]
    private let ventas = tbcCollectionID("ventas")
    private let general = tbcCollectionID("general")

    /// Transporte: Ventas con 2 páginas; General con su fixture (o 500 si `generalDown`); resto vacío.
    private func makeTransport(generalDown: FailSwitch = FailSwitch()) throws -> MockTransport {
        let page1 = try fixture("tasks_ventas_page1")
        let page2 = try fixture("tasks_ventas_page2")
        let general = try fixture("tasks_general")
        return MockTransport { request in
            switch queryValue(request, "section") ?? "" {
            case "1219500158564901":
                return MockResponse(body: queryValue(request, "offset") == nil ? page1 : page2)
            case "1214164017398877":
                if generalDown.isOn {
                    return MockResponse(status: 500, body: Data(#"{"errors":[{"message":"Server Error"}]}"#.utf8))
                }
                return MockResponse(body: general)
            default:
                return MockResponse(body: Data(#"{"data":[],"next_page":null}"#.utf8))
            }
        }
    }

    private func makeMonitor(
        enabling keys: Set<String>,
        transport: HTTPTransport,
        storeURL: URL,
        now: @escaping @Sendable () -> Date
    ) -> IncidentMonitor {
        IncidentMonitor(sources: [presetSource(enabling: keys, transport: transport)], storeURL: storeURL, now: now)
    }

    // MARK: - Punta a punta

    func testEndToEndPollPersistsAndReloads() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        // Subcarpeta inexistente: el monitor debe crearla al persistir.
        let storeURL = tempDir.appendingPathComponent("Notchwatch/state.json")
        let transport = try makeTransport()
        let now = fixedNow
        let monitor = makeMonitor(enabling: ["ventas"], transport: transport, storeURL: storeURL, now: { now })

        // 1º poll (primera ejecución): solo la reciente es nueva; el resto se da por visto.
        let first = await monitor.poll()
        XCTAssertTrue(first.errors.isEmpty)
        XCTAssertEqual(first.date, fixedNow)
        XCTAssertEqual(first.newIncidents.map(\.id), ["1211000000000001"])
        XCTAssertEqual(first.newIncidents.first?.priority, .urgente)
        XCTAssertEqual(first.newIncidents.first?.collectionID, ventas)
        XCTAssertEqual(first.pending.map(\.id), ["1211000000000001"])
        // Dos páginas de Ventas más la lectura de subtareas asignadas (una por sondeo).
        XCTAssertEqual(transport.requests.filter { queryValue($0, "section") != nil }.count, 2)
        XCTAssertEqual(transport.requests.filter { queryValue($0, "assignee") == "me" }.count, 1)

        var persisted = try loadStore(at: storeURL)
        XCTAssertTrue(persisted.initialized)
        XCTAssertEqual(persisted.seen, ventasOld)
        XCTAssertEqual(persisted.baselinedCollections, [ventas])

        // 2º poll: sigue pendiente pero no se vuelve a avisar.
        let second = await monitor.poll()
        XCTAssertTrue(second.newIncidents.isEmpty)
        XCTAssertEqual(second.pending.map(\.id), ["1211000000000001"])

        // Otro monitor con el mismo fichero recarga el estado: las vistas siguen vistas y la
        // pendiente se avisa una vez en la nueva sesión.
        let reloaded = makeMonitor(enabling: ["ventas"], transport: transport, storeURL: storeURL, now: { now })
        let afterReload = await reloaded.poll()
        XCTAssertEqual(afterReload.newIncidents.map(\.id), ["1211000000000001"])
        XCTAssertEqual(afterReload.pending.map(\.id), ["1211000000000001"])

        // Marcar vista la quita de pendientes y se persiste.
        await reloaded.markSeen("1211000000000001")
        persisted = try loadStore(at: storeURL)
        XCTAssertEqual(persisted.seen, ventasOld.union(["1211000000000001"]))
        let afterMarkSeen = await reloaded.poll()
        XCTAssertTrue(afterMarkSeen.newIncidents.isEmpty)
        XCTAssertTrue(afterMarkSeen.pending.isEmpty)

        // Una tercera instancia ya no tiene nada pendiente.
        let third = makeMonitor(enabling: ["ventas"], transport: transport, storeURL: storeURL, now: { now })
        let afterSecondReload = await third.poll()
        XCTAssertTrue(afterSecondReload.newIncidents.isEmpty)
        XCTAssertTrue(afterSecondReload.pending.isEmpty)
    }

    func testSnoozeHidesUntilExpiryAndPersists() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let transport = try makeTransport()
        let clock = TestClock(fixedNow)
        let monitor = makeMonitor(enabling: ["ventas"], transport: transport, storeURL: storeURL, now: { clock.now })

        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.id), ["1211000000000001"])

        await monitor.snooze("1211000000000001", for: 900)
        XCTAssertEqual(
            try loadStore(at: storeURL).snoozedUntil["1211000000000001"],
            fixedNow.addingTimeInterval(900)
        )

        // Pospuesta: pendiente pero no nueva.
        clock.now = fixedNow.addingTimeInterval(60)
        let during = await monitor.poll()
        XCTAssertTrue(during.newIncidents.isEmpty)
        XCTAssertEqual(during.pending.map(\.id), ["1211000000000001"])

        // El snooze sobrevive a un reinicio.
        let reloaded = makeMonitor(enabling: ["ventas"], transport: transport, storeURL: storeURL, now: { clock.now })
        let afterReload = await reloaded.poll()
        XCTAssertTrue(afterReload.newIncidents.isEmpty)
        XCTAssertEqual(afterReload.pending.map(\.id), ["1211000000000001"])

        // Vencido el snooze: se vuelve a avisar una sola vez.
        clock.now = fixedNow.addingTimeInterval(901)
        let expired = await reloaded.poll()
        XCTAssertEqual(expired.newIncidents.map(\.id), ["1211000000000001"])
        XCTAssertNil(try loadStore(at: storeURL).snoozedUntil["1211000000000001"])
        let again = await reloaded.poll()
        XCTAssertTrue(again.newIncidents.isEmpty)
        XCTAssertEqual(again.pending.map(\.id), ["1211000000000001"])
    }

    // MARK: - Errores por colección

    func testErrorInOneCollectionDoesNotBreakOthers() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let transport = try makeTransport(generalDown: FailSwitch(true))
        let now = fixedNow
        let monitor = makeMonitor(enabling: ["ventas", "general"], transport: transport, storeURL: storeURL, now: { now })

        let outcome = await monitor.poll()

        XCTAssertEqual(outcome.errors, [general: .http(500, "Server Error")])
        XCTAssertEqual(outcome.newIncidents.map(\.id), ["1211000000000001"])
        XCTAssertEqual(outcome.pending.map(\.id), ["1211000000000001"])
    }

    func testFirstRunWithFailingCollectionBaselinesItWhenItRecovers() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let generalDown = FailSwitch(true)
        let transport = try makeTransport(generalDown: generalDown)
        let clock = TestClock(fixedNow)
        let monitor = makeMonitor(enabling: ["ventas", "general"], transport: transport, storeURL: storeURL, now: { clock.now })

        // Primera ejecución con General caído.
        let first = await monitor.poll()
        XCTAssertEqual(first.errors[general], .http(500, "Server Error"))
        XCTAssertEqual(first.newIncidents.map(\.id), ["1211000000000001"])
        var persisted = try loadStore(at: storeURL)
        XCTAssertTrue(persisted.initialized)
        XCTAssertEqual(persisted.baselinedCollections, [ventas])

        // Una hora después General sigue caído: la incidencia avisada NO se da por vista sola.
        clock.now = fixedNow.addingTimeInterval(3600)
        let second = await monitor.poll()
        XCTAssertEqual(second.errors[general], .http(500, "Server Error"))
        XCTAssertTrue(second.newIncidents.isEmpty)
        XCTAssertEqual(second.pending.map(\.id), ["1211000000000001"])

        // General se recupera: sus incidencias antiguas se dan por vistas sin avisar.
        generalDown.isOn = false
        let third = await monitor.poll()
        XCTAssertTrue(third.errors.isEmpty)
        XCTAssertTrue(third.newIncidents.isEmpty)
        XCTAssertEqual(third.pending.map(\.id), ["1211000000000001"])
        persisted = try loadStore(at: storeURL)
        XCTAssertEqual(persisted.baselinedCollections, [ventas, general])
        XCTAssertTrue(persisted.seen.isSuperset(of: generalIDs))
    }

    func testFailingCollectionKeepsLastKnownIncidents() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let failing = FailSwitch()
        let generalBody = try fixture("tasks_general")
        let transport = MockTransport { _ in
            failing.isOn ? MockResponse(status: 503, body: Data("caído".utf8)) : MockResponse(body: generalBody)
        }
        // 07:05: 1212000000000001 (07:00) es reciente; 1212000000000002 (06:45) es antigua.
        let now = isoDate("2026-10-14T07:05:00Z")
        let monitor = makeMonitor(enabling: ["general"], transport: transport, storeURL: storeURL, now: { now })

        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.id), ["1212000000000001"])
        XCTAssertEqual(first.pending.map(\.id), ["1212000000000001"])

        // Sustituir las fuentes por otras equivalentes (mismo id) conserva la caché de General.
        await monitor.updateSources([presetSource(enabling: ["general"], transport: transport)])
        failing.isOn = true
        let second = await monitor.poll()
        XCTAssertEqual(second.errors, [general: .http(503, "caído")])
        XCTAssertTrue(second.newIncidents.isEmpty)
        // Con la última lista conocida la pendiente sigue ahí y no se pierde el estado.
        XCTAssertEqual(second.pending.map(\.id), ["1212000000000001"])
        XCTAssertEqual(try loadStore(at: storeURL).seen, ["1212000000000002"])
    }

    // MARK: - Activar / desactivar colecciones

    func testReenabledCollectionIsBaselinedInsteadOfFlooding() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let transport = try makeTransport()
        let now = fixedNow
        let monitor = makeMonitor(enabling: ["ventas", "general"], transport: transport, storeURL: storeURL, now: { now })
        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.id), ["1211000000000001"])

        // Se desactiva General: su estado se purga y pierde la línea base.
        await monitor.updateSources([presetSource(enabling: ["ventas"], transport: transport)])
        let withoutGeneral = await monitor.poll()
        XCTAssertEqual(withoutGeneral.pending.map(\.id), ["1211000000000001"])
        var persisted = try loadStore(at: storeURL)
        XCTAssertEqual(persisted.baselinedCollections, [ventas])
        XCTAssertTrue(persisted.seen.isDisjoint(with: generalIDs))

        // Al reactivarlo, sus incidencias antiguas no se avisan como nuevas.
        await monitor.updateSources([presetSource(enabling: ["ventas", "general"], transport: transport)])
        let reenabled = await monitor.poll()
        XCTAssertTrue(reenabled.newIncidents.isEmpty)
        XCTAssertEqual(reenabled.pending.map(\.id), ["1211000000000001"])
        persisted = try loadStore(at: storeURL)
        XCTAssertEqual(persisted.baselinedCollections, [ventas, general])
        XCTAssertTrue(persisted.seen.isSuperset(of: generalIDs))
    }

    func testNewlyEnabledCollectionOnlyAnnouncesRecentIncidents() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let transport = try makeTransport()
        // 07:05: 1212000000000001 (07:00) es reciente; 1212000000000002 (06:45) es antigua.
        let now = isoDate("2026-10-14T07:05:00Z")
        // Finanzas responde vacío.
        let monitor = makeMonitor(enabling: ["finanzas"], transport: transport, storeURL: storeURL, now: { now })
        let empty = await monitor.poll()
        XCTAssertTrue(empty.pending.isEmpty)

        await monitor.updateSources([presetSource(enabling: ["finanzas", "general"], transport: transport)])
        let outcome = await monitor.poll()

        XCTAssertEqual(outcome.newIncidents.map(\.id), ["1212000000000001"])
        XCTAssertEqual(outcome.pending.map(\.id), ["1212000000000001"])
        XCTAssertEqual(try loadStore(at: storeURL).seen, ["1212000000000002"])
    }

    func testNoEnabledCollectionsDoesNotPollNorTouchState() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let transport = try makeTransport()
        let now = fixedNow
        let monitor = makeMonitor(enabling: [], transport: transport, storeURL: storeURL, now: { now })

        let outcome = await monitor.poll()

        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(outcome.newIncidents.isEmpty)
        XCTAssertTrue(outcome.pending.isEmpty)
        XCTAssertTrue(outcome.errors.isEmpty)
        XCTAssertEqual(outcome.date, fixedNow)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))

        // Al activar una colección se hace la primera ejecución con normalidad.
        await monitor.updateSources([presetSource(enabling: ["ventas"], transport: transport)])
        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.id), ["1211000000000001"])
        XCTAssertEqual(try loadStore(at: storeURL).seen, ventasOld)
    }

    func testNoSourcesAtAllPollsNothing() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let monitor = IncidentMonitor(sources: [], storeURL: storeURL, now: { self.fixedNow })

        let outcome = await monitor.poll()

        XCTAssertTrue(outcome.pending.isEmpty)
        XCTAssertTrue(outcome.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    // MARK: - Credenciales y estado en disco

    func testTokenChangeKeepsStateAndServesCacheWhileFailing() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let goodTransport = try makeTransport()
        let badTransport = MockTransport { _ in
            MockResponse(status: 401, body: Data(#"{"errors":[{"message":"Not Authorized"}]}"#.utf8))
        }
        let now = fixedNow
        let monitor = makeMonitor(enabling: ["ventas"], transport: goodTransport, storeURL: storeURL, now: { now })

        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.id), ["1211000000000001"])

        // Token inválido en la misma fuente: 401 por colección; la caché se mantiene y el estado no se pierde.
        await monitor.updateSources([presetSource(enabling: ["ventas"], token: "malo", transport: badTransport)])
        let failed = await monitor.poll()
        XCTAssertEqual(failed.errors, [ventas: .unauthorized])
        XCTAssertTrue(failed.newIncidents.isEmpty)
        XCTAssertEqual(failed.pending.map(\.id), ["1211000000000001"])
        XCTAssertEqual(badTransport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer malo")
        XCTAssertEqual(try loadStore(at: storeURL).seen, ventasOld)

        // Token corregido: vuelve la pendiente, sin repetir el aviso de esta sesión.
        await monitor.updateSources([presetSource(enabling: ["ventas"], transport: goodTransport)])
        let recovered = await monitor.poll()
        XCTAssertTrue(recovered.errors.isEmpty)
        XCTAssertTrue(recovered.newIncidents.isEmpty)
        XCTAssertEqual(recovered.pending.map(\.id), ["1211000000000001"])
    }

    func testCorruptStoreFileStartsFresh() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        try Data("esto no es json".utf8).write(to: storeURL)
        let now = fixedNow
        let monitor = makeMonitor(enabling: ["ventas"], transport: try makeTransport(), storeURL: storeURL, now: { now })

        let first = await monitor.poll()

        XCTAssertEqual(first.newIncidents.map(\.id), ["1211000000000001"])
        let persisted = try loadStore(at: storeURL)
        XCTAssertTrue(persisted.initialized)
        XCTAssertEqual(persisted.seen, ventasOld)
    }

    func testStoreDecodesFileWithoutBaselinedCollections() throws {
        let json = #"{"initialized":true,"seen":["a"],"snoozedUntil":{"b":"2026-10-14T08:35:00Z"}}"#
        let store = try SeenStore.makeDecoder().decode(SeenStore.self, from: Data(json.utf8))

        XCTAssertTrue(store.initialized)
        XCTAssertEqual(store.seen, ["a"])
        XCTAssertEqual(store.snoozedUntil["b"], isoDate("2026-10-14T08:35:00Z"))
        XCTAssertTrue(store.baselinedCollections.isEmpty)
        XCTAssertTrue(store.assignees.isEmpty)
    }

    func testStoreEncodesBaselinedCollectionsKey() throws {
        var store = SeenStore()
        store.baselinedCollections = ["x/y"]
        let data = try SeenStore.makeEncoder().encode(store)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["baselinedCollections"] as? [String], ["x/y"])
        XCTAssertNil(object["baselinedProjects"])
    }
}

// MARK: - Varias fuentes

final class IncidentMonitorMultiSourceTests: XCTestCase {
    private let now = isoDate("2026-10-14T10:00:00Z")

    private func incident(_ id: String, in collection: WatchedCollection, age: TimeInterval = 60) -> Incident {
        Incident(id: id, collectionID: collection.id, collectionName: collection.name, name: id, createdAt: now.addingTimeInterval(-age))
    }

    private let alpha = WatchedCollection(id: "a/uno", name: "Uno")
    private let beta = WatchedCollection(id: "b/dos", name: "Dos")
    private let gamma = WatchedCollection(id: "b/tres", name: "Tres", enabled: false)

    func testPollsEveryEnabledCollectionOfEverySource() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let a = FakeSource(id: "a", collections: [alpha], incidents: [alpha.id: [incident("a1", in: alpha)]])
        let b = FakeSource(id: "b", collections: [beta, gamma], incidents: [
            beta.id: [incident("b1", in: beta)],
            gamma.id: [incident("g1", in: gamma)],
        ])
        let monitor = IncidentMonitor(sources: [a, b], storeURL: tempDir.appendingPathComponent("s.json"), now: { self.now })

        let outcome = await monitor.poll()

        XCTAssertEqual(Set(outcome.newIncidents.map(\.id)), ["a1", "b1"])
        XCTAssertEqual(Set(outcome.pending.map(\.collectionID)), [alpha.id, beta.id])
        XCTAssertTrue(outcome.errors.isEmpty)
        XCTAssertEqual(try loadStore(at: tempDir.appendingPathComponent("s.json")).baselinedCollections, [alpha.id, beta.id])
    }

    func testFailingSourceUsesLastKnownAndKeysErrorByCollection() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let a = FakeSource(id: "a", collections: [alpha], incidents: [alpha.id: [incident("a1", in: alpha)]])
        let b = FakeSource(id: "b", collections: [beta], incidents: [beta.id: [incident("b1", in: beta)]])
        let monitor = IncidentMonitor(sources: [a, b], storeURL: tempDir.appendingPathComponent("s.json"), now: { self.now })

        let first = await monitor.poll()
        XCTAssertEqual(Set(first.newIncidents.map(\.id)), ["a1", "b1"])

        b.setFailure(.network("sin red"), for: beta.id)
        let second = await monitor.poll()

        XCTAssertEqual(second.errors, [beta.id: .network("sin red")])
        XCTAssertTrue(second.newIncidents.isEmpty)
        XCTAssertEqual(Set(second.pending.map(\.id)), ["a1", "b1"])
    }

    func testUpdateSourcesDropsCacheOfRemovedOrReownedCollections() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let a = FakeSource(id: "a", collections: [alpha], incidents: [alpha.id: [incident("a1", in: alpha)]])
        let b = FakeSource(id: "b", collections: [beta], incidents: [beta.id: [incident("b1", in: beta)]])
        let monitor = IncidentMonitor(sources: [a, b], storeURL: tempDir.appendingPathComponent("s.json"), now: { self.now })
        _ = await monitor.poll()

        // La colección «b/dos» pasa a servirla otra fuente («c») y falla: sin caché, no aparece.
        let c = FakeSource(id: "c", collections: [beta])
        c.setFailure(.unauthorized, for: beta.id)
        a.setFailure(.rateLimited(retryAfter: nil), for: alpha.id)
        await monitor.updateSources([a, c])
        let outcome = await monitor.poll()

        XCTAssertEqual(outcome.errors, [alpha.id: .rateLimited(retryAfter: nil), beta.id: .unauthorized])
        // «a» mantiene su caché (misma fuente); «b/dos» la perdió al cambiar de dueño.
        XCTAssertEqual(outcome.pending.map(\.id), ["a1"])

        // Si la colección desaparece del todo, tampoco se sirve de la caché al volver con otra fuente.
        await monitor.updateSources([a])
        let d = FakeSource(id: "b", collections: [beta])
        d.setFailure(.unauthorized, for: beta.id)
        await monitor.updateSources([a, d])
        let afterReturn = await monitor.poll()
        XCTAssertEqual(afterReturn.pending.map(\.id), ["a1"])
        XCTAssertEqual(afterReturn.errors[beta.id], .unauthorized)
    }

    func testSameSourceIDKeepsCacheAcrossUpdate() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let b = FakeSource(id: "b", collections: [beta], incidents: [beta.id: [incident("b1", in: beta)]])
        let monitor = IncidentMonitor(sources: [b], storeURL: tempDir.appendingPathComponent("s.json"), now: { self.now })
        _ = await monitor.poll()

        let replacement = FakeSource(id: "b", collections: [beta])
        replacement.setFailure(.http(500, "x"), for: beta.id)
        await monitor.updateSources([replacement])
        let outcome = await monitor.poll()

        XCTAssertEqual(outcome.errors, [beta.id: .http(500, "x")])
        XCTAssertEqual(outcome.pending.map(\.id), ["b1"])
    }

    func testNonSourceErrorsBecomeNetwork() async throws {
        struct Boom: Error {}
        final class ThrowingSource: IncidentSource {
            let id = "t"
            let kind: SourceKind = .asana
            let displayName = "t"
            let collections = [WatchedCollection(id: "t/x", name: "X")]
            let capabilities: SourceCapabilities = []
            func identity() async throws -> SourceIdentity { SourceIdentity(userID: "1", name: "t") }
            func openIncidents(in collection: WatchedCollection) async throws -> [Incident] { throw Boom() }
            func perform(_ action: IncidentAction, on incident: Incident) async throws {}
        }
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let monitor = IncidentMonitor(sources: [ThrowingSource()], storeURL: tempDir.appendingPathComponent("s.json"), now: { self.now })

        let outcome = await monitor.poll()

        guard case .network = outcome.errors["t/x"] else {
            return XCTFail("Error inesperado: \(String(describing: outcome.errors["t/x"]))")
        }
    }
}

// MARK: - Alcance «Solo las mías»

final class IncidentMonitorScopeTests: XCTestCase {
    private let clock = TestClock(isoDate("2026-10-14T10:00:00Z"))
    private let collection = WatchedCollection(id: "a/uno", name: "Uno")
    private let joan = SourceIdentity(userID: "u-joan", name: "Joan")
    private let ana = SourceIdentity(userID: "u-ana", name: "Ana")

    private func incident(_ id: String, assignee: SourceIdentity? = nil, age: TimeInterval = 60) -> Incident {
        Incident(
            id: id,
            collectionID: collection.id,
            collectionName: collection.name,
            name: id,
            createdAt: clock.now.addingTimeInterval(-age),
            assigneeID: assignee?.userID,
            assigneeName: assignee?.name
        )
    }

    private func makeMonitor(source: FakeSource, storeURL: URL) -> IncidentMonitor {
        let clock = clock
        return IncidentMonitor(sources: [source], storeURL: storeURL, now: { clock.now })
    }

    func testMineScopeOnlyAnnouncesIncidentsAssignedToUserButKeepsAllPending() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let source = FakeSource(id: "a", collections: [collection], incidents: [collection.id: [
            incident("mia", assignee: ana),
            incident("de-joan", assignee: joan),
            incident("sin-asignar"),
        ]])
        let monitor = makeMonitor(source: source, storeURL: tempDir.appendingPathComponent("s.json"))
        await monitor.updateScope(.mine, for: ana)

        let outcome = await monitor.poll()

        XCTAssertEqual(outcome.newIncidents.map(\.id), ["mia"])
        XCTAssertEqual(Set(outcome.pending.map(\.id)), ["mia", "de-joan", "sin-asignar"])
    }

    func testIncidentReassignedToUserIsAnnouncedAsNew() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        // «antigua» se da por vista en la línea base; «reciente» queda pendiente sin avisar (es de Joan).
        let source = FakeSource(id: "a", collections: [collection], incidents: [collection.id: [
            incident("antigua", assignee: joan, age: 3600),
            incident("reciente", assignee: joan),
        ]])
        let monitor = makeMonitor(source: source, storeURL: tempDir.appendingPathComponent("s.json"))
        await monitor.updateScope(.mine, for: ana)

        let first = await monitor.poll()
        XCTAssertTrue(first.newIncidents.isEmpty)
        XCTAssertEqual(first.pending.map(\.id), ["reciente"])

        source.setIncidents([
            incident("antigua", assignee: ana, age: 3600),
            incident("reciente", assignee: ana),
        ], for: collection.id)
        let second = await monitor.poll()

        XCTAssertEqual(Set(second.newIncidents.map(\.id)), ["antigua", "reciente"])
        XCTAssertEqual(Set(second.pending.map(\.id)), ["antigua", "reciente"])

        let third = await monitor.poll()
        XCTAssertTrue(third.newIncidents.isEmpty)
    }

    func testReassignmentOverridesSeenAndSnoozed() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let source = FakeSource(id: "a", collections: [collection], incidents: [collection.id: [
            incident("vista", assignee: joan),
            incident("pospuesta", assignee: joan),
        ]])
        let monitor = makeMonitor(source: source, storeURL: tempDir.appendingPathComponent("s.json"))
        await monitor.updateScope(.mine, for: ana)
        _ = await monitor.poll()
        await monitor.markSeen("vista")
        await monitor.snooze("pospuesta", for: 3600)

        source.setIncidents([
            incident("vista", assignee: ana),
            incident("pospuesta", assignee: ana),
        ], for: collection.id)
        let outcome = await monitor.poll()

        XCTAssertEqual(Set(outcome.newIncidents.map(\.id)), ["vista", "pospuesta"])
    }

    func testReassignmentIsDetectedAfterRestart() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("s.json")
        let source = FakeSource(id: "a", collections: [collection], incidents: [collection.id: [
            incident("antigua", assignee: joan, age: 3600),
        ]])
        let before = makeMonitor(source: source, storeURL: storeURL)
        await before.updateScope(.mine, for: ana)
        _ = await before.poll()
        XCTAssertEqual(try loadStore(at: storeURL).assignees["antigua"], Assignee(id: joan.userID, name: joan.name))

        source.setIncidents([incident("antigua", assignee: ana, age: 3600)], for: collection.id)
        let after = makeMonitor(source: source, storeURL: storeURL)
        await after.updateScope(.mine, for: ana)
        let outcome = await after.poll()

        XCTAssertEqual(outcome.newIncidents.map(\.id), ["antigua"])
    }

    func testIncidentClaimedFromTheAppIsNotAnnouncedAgain() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let source = FakeSource(id: "a", collections: [collection], incidents: [collection.id: [
            incident("antigua", age: 3600),
        ]])
        let monitor = makeMonitor(source: source, storeURL: tempDir.appendingPathComponent("s.json"))
        await monitor.updateScope(.mine, for: ana)
        _ = await monitor.poll()

        await monitor.claim("antigua")
        source.setIncidents([incident("antigua", assignee: ana, age: 3600)], for: collection.id)
        let claimed = await monitor.poll()
        XCTAssertTrue(claimed.newIncidents.isEmpty)
        XCTAssertTrue(claimed.pending.isEmpty)

        // La reclamación vale una vez: si luego se la quitan y se la devuelven, se avisa.
        source.setIncidents([incident("antigua", assignee: joan, age: 3600)], for: collection.id)
        _ = await monitor.poll()
        source.setIncidents([incident("antigua", assignee: ana, age: 3600)], for: collection.id)
        let reassigned = await monitor.poll()
        XCTAssertEqual(reassigned.newIncidents.map(\.id), ["antigua"])
    }

    func testMineScopeWithoutKnownUserWaitsForIt() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let source = FakeSource(id: "a", collections: [collection], incidents: [collection.id: [
            incident("mia", assignee: ana),
        ]])
        let monitor = makeMonitor(source: source, storeURL: tempDir.appendingPathComponent("s.json"))
        await monitor.updateScope(.mine, for: nil)

        let unknown = await monitor.poll()
        XCTAssertTrue(unknown.newIncidents.isEmpty)
        XCTAssertEqual(unknown.pending.map(\.id), ["mia"])

        await monitor.updateScope(.mine, for: ana)
        let known = await monitor.poll()
        XCTAssertEqual(known.newIncidents.map(\.id), ["mia"])
    }

    func testAllScopeAnnouncesEverythingAndIgnoresReassignments() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let source = FakeSource(id: "a", collections: [collection], incidents: [collection.id: [
            incident("antigua", assignee: joan, age: 3600),
            incident("de-joan", assignee: joan),
        ]])
        let monitor = makeMonitor(source: source, storeURL: tempDir.appendingPathComponent("s.json"))
        await monitor.updateScope(.all, for: ana)

        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.id), ["de-joan"])

        source.setIncidents([
            incident("antigua", assignee: ana, age: 3600),
            incident("de-joan", assignee: ana),
        ], for: collection.id)
        let second = await monitor.poll()
        XCTAssertTrue(second.newIncidents.isEmpty)
        XCTAssertEqual(second.pending.map(\.id), ["de-joan"])
    }

    func testClosedIncidentsDropTheirRecordedAssignee() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("s.json")
        let source = FakeSource(id: "a", collections: [collection], incidents: [collection.id: [
            incident("abierta", assignee: joan),
        ]])
        let monitor = makeMonitor(source: source, storeURL: storeURL)
        _ = await monitor.poll()
        XCTAssertEqual(Set(try loadStore(at: storeURL).assignees.keys), ["abierta"])

        source.setIncidents([], for: collection.id)
        _ = await monitor.poll()
        XCTAssertTrue(try loadStore(at: storeURL).assignees.isEmpty)
    }
}
