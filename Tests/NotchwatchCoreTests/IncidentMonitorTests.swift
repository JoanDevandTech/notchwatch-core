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
    private let generalGids: Set<String> = ["1212000000000001", "1212000000000002"]

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

    // MARK: - Punta a punta

    func testEndToEndPollPersistsAndReloads() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        // Subcarpeta inexistente: el monitor debe crearla al persistir.
        let storeURL = tempDir.appendingPathComponent("Notchwatch/state.json")
        let transport = try makeTransport()
        let client = AsanaClient(token: "tok", transport: transport)
        let config = defaultConfig(enabling: ["ventas"])
        let now = fixedNow
        let monitor = IncidentMonitor(client: client, config: config, storeURL: storeURL, now: { now })

        // 1º poll (primera ejecución): solo la reciente es nueva; el resto se da por visto.
        let first = await monitor.poll()
        XCTAssertTrue(first.errors.isEmpty)
        XCTAssertEqual(first.date, fixedNow)
        XCTAssertEqual(first.newIncidents.map(\.gid), ["1211000000000001"])
        XCTAssertEqual(first.newIncidents.first?.priority, .urgente)
        XCTAssertEqual(first.pending.map(\.gid), ["1211000000000001"])
        XCTAssertEqual(transport.requests.count, 2) // dos páginas de Ventas

        var persisted = try loadStore(at: storeURL)
        XCTAssertTrue(persisted.initialized)
        XCTAssertEqual(persisted.seen, ventasOld)
        XCTAssertEqual(persisted.baselinedProjects, ["ventas"])

        // 2º poll: sigue pendiente pero no se vuelve a avisar.
        let second = await monitor.poll()
        XCTAssertTrue(second.newIncidents.isEmpty)
        XCTAssertEqual(second.pending.map(\.gid), ["1211000000000001"])

        // Otro monitor con el mismo fichero recarga el estado: las vistas siguen vistas y la
        // pendiente se avisa una vez en la nueva sesión.
        let reloaded = IncidentMonitor(client: client, config: config, storeURL: storeURL, now: { now })
        let afterReload = await reloaded.poll()
        XCTAssertEqual(afterReload.newIncidents.map(\.gid), ["1211000000000001"])
        XCTAssertEqual(afterReload.pending.map(\.gid), ["1211000000000001"])

        // Marcar vista la quita de pendientes y se persiste.
        await reloaded.markSeen("1211000000000001")
        persisted = try loadStore(at: storeURL)
        XCTAssertEqual(persisted.seen, ventasOld.union(["1211000000000001"]))
        let afterMarkSeen = await reloaded.poll()
        XCTAssertTrue(afterMarkSeen.newIncidents.isEmpty)
        XCTAssertTrue(afterMarkSeen.pending.isEmpty)

        // Una tercera instancia ya no tiene nada pendiente.
        let third = IncidentMonitor(client: client, config: config, storeURL: storeURL, now: { now })
        let afterSecondReload = await third.poll()
        XCTAssertTrue(afterSecondReload.newIncidents.isEmpty)
        XCTAssertTrue(afterSecondReload.pending.isEmpty)
    }

    func testSnoozeHidesUntilExpiryAndPersists() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let client = AsanaClient(token: "tok", transport: try makeTransport())
        let config = defaultConfig(enabling: ["ventas"])
        let clock = TestClock(fixedNow)
        let monitor = IncidentMonitor(client: client, config: config, storeURL: storeURL, now: { clock.now })

        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.gid), ["1211000000000001"])

        await monitor.snooze("1211000000000001", for: 900)
        XCTAssertEqual(
            try loadStore(at: storeURL).snoozedUntil["1211000000000001"],
            fixedNow.addingTimeInterval(900)
        )

        // Pospuesta: pendiente pero no nueva.
        clock.now = fixedNow.addingTimeInterval(60)
        let during = await monitor.poll()
        XCTAssertTrue(during.newIncidents.isEmpty)
        XCTAssertEqual(during.pending.map(\.gid), ["1211000000000001"])

        // El snooze sobrevive a un reinicio.
        let reloaded = IncidentMonitor(client: client, config: config, storeURL: storeURL, now: { clock.now })
        let afterReload = await reloaded.poll()
        XCTAssertTrue(afterReload.newIncidents.isEmpty)
        XCTAssertEqual(afterReload.pending.map(\.gid), ["1211000000000001"])

        // Vencido el snooze: se vuelve a avisar una sola vez.
        clock.now = fixedNow.addingTimeInterval(901)
        let expired = await reloaded.poll()
        XCTAssertEqual(expired.newIncidents.map(\.gid), ["1211000000000001"])
        XCTAssertNil(try loadStore(at: storeURL).snoozedUntil["1211000000000001"])
        let again = await reloaded.poll()
        XCTAssertTrue(again.newIncidents.isEmpty)
        XCTAssertEqual(again.pending.map(\.gid), ["1211000000000001"])
    }

    // MARK: - Errores por proyecto

    func testErrorInOneProjectDoesNotBreakOthers() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let client = AsanaClient(token: "tok", transport: try makeTransport(generalDown: FailSwitch(true)))
        let now = fixedNow
        let monitor = IncidentMonitor(
            client: client,
            config: defaultConfig(enabling: ["ventas", "general"]),
            storeURL: storeURL,
            now: { now }
        )

        let outcome = await monitor.poll()

        XCTAssertEqual(outcome.errors, ["general": .http(500, "Server Error")])
        XCTAssertEqual(outcome.newIncidents.map(\.gid), ["1211000000000001"])
        XCTAssertEqual(outcome.pending.map(\.gid), ["1211000000000001"])
    }

    func testFirstRunWithFailingProjectBaselinesItWhenItRecovers() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let generalDown = FailSwitch(true)
        let client = AsanaClient(token: "tok", transport: try makeTransport(generalDown: generalDown))
        let clock = TestClock(fixedNow)
        let monitor = IncidentMonitor(
            client: client,
            config: defaultConfig(enabling: ["ventas", "general"]),
            storeURL: storeURL,
            now: { clock.now }
        )

        // Primera ejecución con General caído.
        let first = await monitor.poll()
        XCTAssertEqual(first.errors["general"], .http(500, "Server Error"))
        XCTAssertEqual(first.newIncidents.map(\.gid), ["1211000000000001"])
        var persisted = try loadStore(at: storeURL)
        XCTAssertTrue(persisted.initialized)
        XCTAssertEqual(persisted.baselinedProjects, ["ventas"])

        // Una hora después General sigue caído: la incidencia avisada NO se da por vista sola.
        clock.now = fixedNow.addingTimeInterval(3600)
        let second = await monitor.poll()
        XCTAssertEqual(second.errors["general"], .http(500, "Server Error"))
        XCTAssertTrue(second.newIncidents.isEmpty)
        XCTAssertEqual(second.pending.map(\.gid), ["1211000000000001"])

        // General se recupera: sus incidencias antiguas se dan por vistas sin avisar.
        generalDown.isOn = false
        let third = await monitor.poll()
        XCTAssertTrue(third.errors.isEmpty)
        XCTAssertTrue(third.newIncidents.isEmpty)
        XCTAssertEqual(third.pending.map(\.gid), ["1211000000000001"])
        persisted = try loadStore(at: storeURL)
        XCTAssertEqual(persisted.baselinedProjects, ["ventas", "general"])
        XCTAssertTrue(persisted.seen.isSuperset(of: generalGids))
    }

    func testFailingProjectKeepsLastKnownIncidents() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let failing = FailSwitch()
        let general = try fixture("tasks_general")
        let transport = MockTransport { _ in
            failing.isOn ? MockResponse(status: 503, body: Data("caído".utf8)) : MockResponse(body: general)
        }
        // 07:05: 1212000000000001 (07:00) es reciente; 1212000000000002 (06:45) es antigua.
        let now = isoDate("2026-10-14T07:05:00Z")
        let monitor = IncidentMonitor(
            client: AsanaClient(token: "tok", transport: transport),
            config: defaultConfig(enabling: ["general"]),
            storeURL: storeURL,
            now: { now }
        )

        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.gid), ["1212000000000001"])
        XCTAssertEqual(first.pending.map(\.gid), ["1212000000000001"])

        // Cambiar la config sin tocar General conserva su caché.
        await monitor.updateConfig(defaultConfig(enabling: ["general"]))
        failing.isOn = true
        let second = await monitor.poll()
        XCTAssertEqual(second.errors, ["general": .http(503, "caído")])
        XCTAssertTrue(second.newIncidents.isEmpty)
        // Con la última lista conocida la pendiente sigue ahí y no se pierde el estado.
        XCTAssertEqual(second.pending.map(\.gid), ["1212000000000001"])
        XCTAssertEqual(try loadStore(at: storeURL).seen, ["1212000000000002"])
    }

    // MARK: - Activar / desactivar proyectos

    func testReenabledProjectIsBaselinedInsteadOfFlooding() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let client = AsanaClient(token: "tok", transport: try makeTransport())
        let now = fixedNow
        let monitor = IncidentMonitor(
            client: client,
            config: defaultConfig(enabling: ["ventas", "general"]),
            storeURL: storeURL,
            now: { now }
        )
        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.gid), ["1211000000000001"])

        // Se desactiva General: su estado se purga y pierde la línea base.
        await monitor.updateConfig(defaultConfig(enabling: ["ventas"]))
        let withoutGeneral = await monitor.poll()
        XCTAssertEqual(withoutGeneral.pending.map(\.gid), ["1211000000000001"])
        var persisted = try loadStore(at: storeURL)
        XCTAssertEqual(persisted.baselinedProjects, ["ventas"])
        XCTAssertTrue(persisted.seen.isDisjoint(with: generalGids))

        // Al reactivarlo, sus incidencias antiguas no se avisan como nuevas.
        await monitor.updateConfig(defaultConfig(enabling: ["ventas", "general"]))
        let reenabled = await monitor.poll()
        XCTAssertTrue(reenabled.newIncidents.isEmpty)
        XCTAssertEqual(reenabled.pending.map(\.gid), ["1211000000000001"])
        persisted = try loadStore(at: storeURL)
        XCTAssertEqual(persisted.baselinedProjects, ["ventas", "general"])
        XCTAssertTrue(persisted.seen.isSuperset(of: generalGids))
    }

    func testNewlyEnabledProjectOnlyAnnouncesRecentIncidents() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let client = AsanaClient(token: "tok", transport: try makeTransport())
        // 07:05: 1212000000000001 (07:00) es reciente; 1212000000000002 (06:45) es antigua.
        let now = isoDate("2026-10-14T07:05:00Z")
        let monitor = IncidentMonitor(
            client: client,
            config: defaultConfig(enabling: ["finanzas"]), // responde vacío
            storeURL: storeURL,
            now: { now }
        )
        let empty = await monitor.poll()
        XCTAssertTrue(empty.pending.isEmpty)

        await monitor.updateConfig(defaultConfig(enabling: ["finanzas", "general"]))
        let outcome = await monitor.poll()

        XCTAssertEqual(outcome.newIncidents.map(\.gid), ["1212000000000001"])
        XCTAssertEqual(outcome.pending.map(\.gid), ["1212000000000001"])
        XCTAssertEqual(try loadStore(at: storeURL).seen, ["1212000000000002"])
    }

    func testNoEnabledProjectsDoesNotPollNorTouchState() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let transport = try makeTransport()
        let now = fixedNow
        let monitor = IncidentMonitor(
            client: AsanaClient(token: "tok", transport: transport),
            config: defaultConfig(enabling: []),
            storeURL: storeURL,
            now: { now }
        )

        let outcome = await monitor.poll()

        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(outcome.newIncidents.isEmpty)
        XCTAssertTrue(outcome.pending.isEmpty)
        XCTAssertTrue(outcome.errors.isEmpty)
        XCTAssertEqual(outcome.date, fixedNow)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))

        // Al activar un proyecto se hace la primera ejecución con normalidad.
        await monitor.updateConfig(defaultConfig(enabling: ["ventas"]))
        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.gid), ["1211000000000001"])
        XCTAssertEqual(try loadStore(at: storeURL).seen, ventasOld)
    }

    // MARK: - Cliente y estado en disco

    func testUpdateClientKeepsStateAcrossTokenChange() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        let good = AsanaClient(token: "bueno", transport: try makeTransport())
        let badTransport = MockTransport { _ in
            MockResponse(status: 401, body: Data(#"{"errors":[{"message":"Not Authorized"}]}"#.utf8))
        }
        let bad = AsanaClient(token: "malo", transport: badTransport)
        let now = fixedNow
        let monitor = IncidentMonitor(
            client: good,
            config: defaultConfig(enabling: ["ventas"]),
            storeURL: storeURL,
            now: { now }
        )

        let first = await monitor.poll()
        XCTAssertEqual(first.newIncidents.map(\.gid), ["1211000000000001"])

        // Token inválido: 401 por proyecto, sin datos de la credencial anterior y sin perder estado.
        await monitor.updateClient(bad)
        let failed = await monitor.poll()
        XCTAssertEqual(failed.errors, ["ventas": .unauthorized])
        XCTAssertTrue(failed.pending.isEmpty)
        XCTAssertEqual(badTransport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer malo")
        XCTAssertEqual(try loadStore(at: storeURL).seen, ventasOld)

        // Token corregido: vuelve la pendiente, sin repetir el aviso de esta sesión.
        await monitor.updateClient(good)
        let recovered = await monitor.poll()
        XCTAssertTrue(recovered.errors.isEmpty)
        XCTAssertTrue(recovered.newIncidents.isEmpty)
        XCTAssertEqual(recovered.pending.map(\.gid), ["1211000000000001"])
    }

    func testCorruptStoreFileStartsFresh() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("state.json")
        try Data("esto no es json".utf8).write(to: storeURL)
        let now = fixedNow
        let monitor = IncidentMonitor(
            client: AsanaClient(token: "tok", transport: try makeTransport()),
            config: defaultConfig(enabling: ["ventas"]),
            storeURL: storeURL,
            now: { now }
        )

        let first = await monitor.poll()

        XCTAssertEqual(first.newIncidents.map(\.gid), ["1211000000000001"])
        let persisted = try loadStore(at: storeURL)
        XCTAssertTrue(persisted.initialized)
        XCTAssertEqual(persisted.seen, ventasOld)
    }

    func testStoreDecodesFileWithoutBaselinedProjects() throws {
        let json = #"{"initialized":true,"seen":["a"],"snoozedUntil":{"b":"2026-10-14T08:35:00Z"}}"#
        let store = try SeenStore.makeDecoder().decode(SeenStore.self, from: Data(json.utf8))

        XCTAssertTrue(store.initialized)
        XCTAssertEqual(store.seen, ["a"])
        XCTAssertEqual(store.snoozedUntil["b"], isoDate("2026-10-14T08:35:00Z"))
        XCTAssertTrue(store.baselinedProjects.isEmpty)
    }
}
