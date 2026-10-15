import Foundation
import XCTest
@testable import NotchwatchCore

final class IncidentDifferTests: XCTestCase {
    private let now = isoDate("2026-10-14T10:00:00Z")

    // MARK: - Primera ejecución

    func testFirstRunMarksOldAsSeenAndNotifiesRecent() {
        let fresh = sampleIncident("a", createdAt: now.addingTimeInterval(-60))
        let old = sampleIncident("b", createdAt: now.addingTimeInterval(-3600))
        let borderline = sampleIncident("c", createdAt: now.addingTimeInterval(-600)) // justo en el límite: antigua
        var store = SeenStore()

        let result = IncidentDiffer.diff(current: [fresh, old, borderline], store: &store, now: now)

        XCTAssertTrue(store.initialized)
        XCTAssertEqual(store.seen, ["b", "c"])
        XCTAssertEqual(result.newIncidents.map(\.gid), ["a"])
        XCTAssertEqual(result.pending.map(\.gid), ["a"])
    }

    func testFirstRunHonoursCustomFreshWindow() {
        let incident = sampleIncident("a", createdAt: now.addingTimeInterval(-1800))
        var store = SeenStore()

        let result = IncidentDiffer.diff(current: [incident], store: &store, now: now, freshWindow: 3600)

        XCTAssertEqual(result.newIncidents.map(\.gid), ["a"])
        XCTAssertTrue(store.seen.isEmpty)
        XCTAssertTrue(store.initialized)
    }

    func testFreshWindowOnlyAppliesToFirstRun() {
        var store = SeenStore()
        _ = IncidentDiffer.diff(current: [], store: &store, now: now)
        XCTAssertTrue(store.initialized)

        // Ya inicializado: una incidencia antigua no vista es nueva.
        let old = sampleIncident("a", createdAt: now.addingTimeInterval(-86_400))
        let result = IncidentDiffer.diff(current: [old], store: &store, now: now)

        XCTAssertEqual(result.newIncidents.map(\.gid), ["a"])
        XCTAssertTrue(store.seen.isEmpty)
    }

    // MARK: - Nuevas y vistas

    func testNewAndSeenAfterInitialization() {
        var store = SeenStore()
        store.initialized = true
        store.seen = ["a"]
        let seen = sampleIncident("a", createdAt: now.addingTimeInterval(-7200))
        let unseen = sampleIncident("b", createdAt: now.addingTimeInterval(-7200)) // antigua pero no vista: nueva

        let result = IncidentDiffer.diff(current: [seen, unseen], store: &store, now: now)

        XCTAssertEqual(result.newIncidents.map(\.gid), ["b"])
        XCTAssertEqual(result.pending.map(\.gid), ["b"])
        XCTAssertEqual(store.seen, ["a"])
    }

    // MARK: - Snooze

    func testActiveSnoozeIsPendingButNotNew() {
        var store = SeenStore()
        store.initialized = true
        store.snoozedUntil = ["a": now.addingTimeInterval(60)]
        let incident = sampleIncident("a", createdAt: now.addingTimeInterval(-60))

        let result = IncidentDiffer.diff(current: [incident], store: &store, now: now)

        XCTAssertTrue(result.newIncidents.isEmpty)
        XCTAssertEqual(result.pending.map(\.gid), ["a"])
        XCTAssertEqual(store.snoozedUntil["a"], now.addingTimeInterval(60))
    }

    func testExpiredSnoozeIsNewAgain() {
        var store = SeenStore()
        store.initialized = true
        store.snoozedUntil = ["a": now.addingTimeInterval(-1)]
        let incident = sampleIncident("a", createdAt: now.addingTimeInterval(-7200))

        let result = IncidentDiffer.diff(current: [incident], store: &store, now: now)

        XCTAssertEqual(result.newIncidents.map(\.gid), ["a"])
        XCTAssertEqual(result.pending.map(\.gid), ["a"])
        XCTAssertNil(store.snoozedUntil["a"])
    }

    func testSnoozeEndingExactlyNowCountsAsExpired() {
        var store = SeenStore()
        store.initialized = true
        store.snoozedUntil = ["a": now]
        let incident = sampleIncident("a", createdAt: now.addingTimeInterval(-7200))

        let result = IncidentDiffer.diff(current: [incident], store: &store, now: now)

        XCTAssertEqual(result.newIncidents.map(\.gid), ["a"])
        XCTAssertNil(store.snoozedUntil["a"])
    }

    // MARK: - Limpieza

    func testCleansClosedIncidents() {
        var store = SeenStore()
        store.initialized = true
        store.seen = ["a", "cerrada"]
        store.snoozedUntil = ["cerrada2": now.addingTimeInterval(300), "b": now.addingTimeInterval(300)]
        let a = sampleIncident("a", createdAt: now)
        let b = sampleIncident("b", createdAt: now)

        let result = IncidentDiffer.diff(current: [a, b], store: &store, now: now)

        XCTAssertEqual(store.seen, ["a"])
        XCTAssertEqual(Set(store.snoozedUntil.keys), ["b"])
        XCTAssertEqual(result.pending.map(\.gid), ["b"])
        XCTAssertTrue(result.newIncidents.isEmpty)
    }

    func testDuplicatedGidAcrossProjectsCountsOnce() {
        var store = SeenStore()
        store.initialized = true
        let first = sampleIncident("a", createdAt: now, projectKey: "ventas")
        let duplicate = sampleIncident("a", createdAt: now, projectKey: "general")

        let result = IncidentDiffer.diff(current: [first, duplicate], store: &store, now: now)

        XCTAssertEqual(result.pending.count, 1)
        XCTAssertEqual(result.pending.first?.projectKey, "ventas")
        XCTAssertEqual(result.newIncidents.count, 1)
    }

    // MARK: - Orden

    func testOrderByPriorityThenDateDesc() {
        var store = SeenStore()
        store.initialized = true
        store.snoozedUntil = ["media-pospuesta": now.addingTimeInterval(600)]
        let incidents = [
            sampleIncident("baja", priority: .baja, createdAt: now.addingTimeInterval(-10)),
            sampleIncident("alta-vieja", priority: .alta, createdAt: now.addingTimeInterval(-500)),
            sampleIncident("ninguna", priority: .ninguna, createdAt: now),
            sampleIncident("media-pospuesta", priority: .media, createdAt: now.addingTimeInterval(-1)),
            sampleIncident("urgente", priority: .urgente, createdAt: now.addingTimeInterval(-9000)),
            sampleIncident("alta-nueva", priority: .alta, createdAt: now.addingTimeInterval(-5)),
            sampleIncident("media", priority: .media, createdAt: now.addingTimeInterval(-20)),
        ]

        let result = IncidentDiffer.diff(current: incidents, store: &store, now: now)

        XCTAssertEqual(
            result.newIncidents.map(\.gid),
            ["urgente", "alta-nueva", "alta-vieja", "media", "baja", "ninguna"]
        )
        // pending incluye la pospuesta, en el mismo orden.
        XCTAssertEqual(
            result.pending.map(\.gid),
            ["urgente", "alta-nueva", "alta-vieja", "media-pospuesta", "media", "baja", "ninguna"]
        )
    }

    func testOrderTieBreaksByGid() {
        var store = SeenStore()
        store.initialized = true
        let incidents = [
            sampleIncident("c", priority: .alta, createdAt: now),
            sampleIncident("a", priority: .alta, createdAt: now),
            sampleIncident("b", priority: .alta, createdAt: now),
        ]

        let result = IncidentDiffer.diff(current: incidents, store: &store, now: now)

        XCTAssertEqual(result.newIncidents.map(\.gid), ["a", "b", "c"])
    }

    // MARK: - Prioridad

    func testPriorityComparableAndLabels() {
        XCTAssertTrue(IncidentPriority.urgente > .alta)
        XCTAssertTrue(IncidentPriority.alta > .media)
        XCTAssertTrue(IncidentPriority.media > .baja)
        XCTAssertTrue(IncidentPriority.baja > .ninguna)
        XCTAssertEqual(
            IncidentPriority.allCases.sorted(by: >),
            [.urgente, .alta, .media, .baja, .ninguna]
        )
        XCTAssertEqual(IncidentPriority.allCases.map(\.label), ["Baja", "Media", "Alta", "Urgente", "Sin prioridad"])
        XCTAssertEqual(IncidentPriority.allCases.filter(\.isLoud), [.alta, .urgente])
    }
}
