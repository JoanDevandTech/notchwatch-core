import Foundation
import XCTest
@testable import NotchwatchCore

final class NotificationPlannerTests: XCTestCase {
    private let now = isoDate("2026-10-14T10:00:00Z")

    /// Incidencia con los datos que forman el subtítulo.
    private func detailed(reporter: String? = nil, module: String? = nil, consoleErrors: Int? = nil) -> Incident {
        var incident = sampleIncident("a", createdAt: now)
        incident.reporter = reporter
        incident.module = module
        incident.consoleErrors = consoleErrors
        return incident
    }

    /// Subtítulo de la notificación individual.
    private func subtitle(_ incident: Incident) -> String {
        NotificationPlanner.payload(for: incident).subtitle
    }

    func testContractConstants() {
        XCTAssertEqual(NotificationPlanner.summaryIdentifier, "notchwatch.summary")
        XCTAssertEqual(NotificationPlanner.maxIndividual, 3)
    }

    // MARK: - Reparto individual / resumen

    func testEmptyInputPlansNothing() {
        XCTAssertEqual(NotificationPlanner.payloads(for: [], asBatch: false), [])
        XCTAssertEqual(NotificationPlanner.payloads(for: [], asBatch: true), [])
        XCTAssertNil(NotificationPlanner.summary(for: []))
    }

    func testSingleIncidentInBatchIsStillIndividual() {
        let incident = sampleIncident("a", priority: .alta, createdAt: now)

        let payloads = NotificationPlanner.payloads(for: [incident], asBatch: true)

        XCTAssertEqual(payloads, [NotificationPlanner.payload(for: incident)])
        XCTAssertEqual(payloads.first?.isSummary, false)
        XCTAssertEqual(payloads.first?.identifier, "a")
    }

    func testTwoIncidentsAreIndividualSortedByPriority() {
        let lowRecent = sampleIncident("baja-nueva", priority: .baja, createdAt: now)
        let highOld = sampleIncident("alta-vieja", priority: .alta, createdAt: now.addingTimeInterval(-3600))

        let payloads = NotificationPlanner.payloads(for: [lowRecent, highOld], asBatch: false)

        XCTAssertEqual(payloads.map(\.identifier), ["alta-vieja", "baja-nueva"])
        XCTAssertEqual(payloads.map(\.incidentGid), ["alta-vieja", "baja-nueva"])
        XCTAssertEqual(payloads.map(\.isSummary), [false, false])
    }

    func testSamePriorityNewestFirst() {
        let old = sampleIncident("vieja", priority: .media, createdAt: now.addingTimeInterval(-600))
        let recent = sampleIncident("nueva", priority: .media, createdAt: now)

        let payloads = NotificationPlanner.payloads(for: [old, recent], asBatch: false)

        XCTAssertEqual(payloads.map(\.identifier), ["nueva", "vieja"])
    }

    func testUpToMaxIndividualStaysIndividual() {
        let incidents = (1...NotificationPlanner.maxIndividual).map { index in
            sampleIncident("i\(index)", createdAt: now.addingTimeInterval(-Double(index)))
        }

        let payloads = NotificationPlanner.payloads(for: incidents.reversed(), asBatch: false)

        XCTAssertEqual(payloads.map(\.identifier), ["i1", "i2", "i3"])
    }

    func testMoreThanMaxIndividualCollapsesIntoSummary() throws {
        let incidents = [
            sampleIncident("baja", priority: .baja, createdAt: now),
            sampleIncident("urgente", priority: .urgente, createdAt: now.addingTimeInterval(-7200)),
            sampleIncident("media", priority: .media, createdAt: now),
            sampleIncident("alta", priority: .alta, createdAt: now),
        ]

        let payloads = NotificationPlanner.payloads(for: incidents, asBatch: false)

        let summary = try XCTUnwrap(NotificationPlanner.summary(for: incidents))
        XCTAssertEqual(payloads, [summary])
        XCTAssertTrue(summary.isSummary)
        XCTAssertEqual(summary.title, "4 incidencias nuevas")
        XCTAssertEqual(summary.body, "Incidencia urgente y 3 más")
    }

    func testBatchOfTwoIsSummary() throws {
        let incidents = [
            sampleIncident("a", priority: .media, createdAt: now),
            sampleIncident("b", priority: .alta, createdAt: now.addingTimeInterval(-60), projectKey: "finanzas"),
        ]

        let payloads = NotificationPlanner.payloads(for: incidents, asBatch: true)

        let summary = try XCTUnwrap(NotificationPlanner.summary(for: incidents))
        XCTAssertEqual(payloads, [summary])
        XCTAssertEqual(summary.title, "2 incidencias nuevas")
        XCTAssertEqual(summary.subtitle, "La más importante: Alta · Finanzas")
        XCTAssertEqual(summary.body, "Incidencia b y 1 más")
    }

    // MARK: - Notificación individual

    func testTitleCombinesPriorityAndApp() {
        let urgent = sampleIncident("a", priority: .urgente, createdAt: now, projectKey: "finanzas")
        let unprioritized = sampleIncident("b", priority: .ninguna, createdAt: now, projectKey: "ventas")

        XCTAssertEqual(NotificationPlanner.payload(for: urgent).title, "Urgente · Finanzas")
        XCTAssertEqual(NotificationPlanner.payload(for: unprioritized).title, "Sin prioridad · Ventas")
    }

    func testSubtitleWithAllParts() {
        let incident = detailed(reporter: "Ana López", module: "Presupuestos", consoleErrors: 3)
        XCTAssertEqual(subtitle(incident), "Reportada por Ana López · Presupuestos · 3 errores de consola")
    }

    func testSubtitleWithSomeParts() {
        XCTAssertEqual(
            subtitle(detailed(reporter: "Ana", consoleErrors: 2)),
            "Reportada por Ana · 2 errores de consola"
        )
        XCTAssertEqual(subtitle(detailed(module: "Reservas")), "Reservas")
        // El reportero se muestra sin espacios en los extremos.
        XCTAssertEqual(subtitle(detailed(reporter: "  Ana \n")), "Reportada por Ana")
    }

    func testSubtitleWithoutPartsIsEmpty() {
        XCTAssertEqual(subtitle(detailed()), "")
        // Vacíos o solo espacios no cuentan.
        XCTAssertEqual(subtitle(detailed(reporter: "   ", module: "")), "")
    }

    func testSubtitleConsoleErrorsSingularAndPlural() {
        XCTAssertEqual(subtitle(detailed(consoleErrors: 1)), "1 error de consola")
        XCTAssertEqual(subtitle(detailed(consoleErrors: 2)), "2 errores de consola")
        XCTAssertEqual(subtitle(detailed(consoleErrors: 12)), "12 errores de consola")
    }

    func testSubtitleOmitsZeroConsoleErrors() {
        XCTAssertEqual(subtitle(detailed(consoleErrors: 0)), "")
        XCTAssertEqual(
            subtitle(detailed(reporter: "Ana", module: "Reservas", consoleErrors: 0)),
            "Reportada por Ana · Reservas"
        )
    }

    func testIndividualPayloadPropagatesGidURLAndThread() throws {
        let url = try XCTUnwrap(URL(string: "https://app.asana.com/0/1219500158564901/1211000000000001"))
        var incident = sampleIncident("1211000000000001", priority: .alta, createdAt: now, projectKey: "traslados")
        incident.name = "No se asigna conductor"
        incident.permalinkURL = url

        XCTAssertEqual(
            NotificationPlanner.payload(for: incident),
            NotificationPayload(
                identifier: "1211000000000001",
                title: "Alta · Traslados",
                subtitle: "",
                body: "No se asigna conductor",
                threadIdentifier: "traslados",
                incidentGid: "1211000000000001",
                url: url,
                isSummary: false
            )
        )
    }

    func testIndividualPayloadWithoutLinkHasNilURL() {
        let payload = NotificationPlanner.payload(for: sampleIncident("a", createdAt: now))
        XCTAssertNil(payload.url)
        XCTAssertEqual(payload.incidentGid, "a")
    }

    // MARK: - Resumen

    func testSummaryOfThreeHighlightsTheMostImportant() throws {
        let earlier = now.addingTimeInterval(-3600)
        var newestUrgent = sampleIncident("urgente-nueva", priority: .urgente, createdAt: now, projectKey: "mitbc")
        // El resumen no hereda el enlace de la más importante.
        newestUrgent.permalinkURL = try XCTUnwrap(URL(string: "https://app.asana.com/0/1/2"))
        let incidents = [
            sampleIncident("media", priority: .media, createdAt: now),
            sampleIncident("urgente-vieja", priority: .urgente, createdAt: earlier, projectKey: "finanzas"),
            newestUrgent,
        ]

        let summary = try XCTUnwrap(NotificationPlanner.summary(for: incidents))

        XCTAssertEqual(
            summary,
            NotificationPayload(
                identifier: NotificationPlanner.summaryIdentifier,
                title: "3 incidencias nuevas",
                subtitle: "La más importante: Urgente · Mi TBC",
                body: "Incidencia urgente-nueva y 2 más",
                threadIdentifier: NotificationPlanner.summaryIdentifier,
                incidentGid: nil,
                url: nil,
                isSummary: true
            )
        )
        // Con asBatch, la misma tanda se resume igual.
        XCTAssertEqual(NotificationPlanner.payloads(for: incidents, asBatch: true), [summary])
    }

    func testSummaryOfOne() throws {
        var incident = sampleIncident("a", priority: .baja, createdAt: now, projectKey: "general")
        incident.permalinkURL = URL(string: "https://app.asana.com/0/1/2")

        let summary = try XCTUnwrap(NotificationPlanner.summary(for: [incident]))

        XCTAssertEqual(summary.title, "1 incidencia nueva")
        XCTAssertEqual(summary.subtitle, "La más importante: Baja · TBC")
        XCTAssertEqual(summary.body, "Incidencia a")
        XCTAssertEqual(summary.identifier, "notchwatch.summary")
        XCTAssertEqual(summary.threadIdentifier, "notchwatch.summary")
        XCTAssertNil(summary.incidentGid)
        XCTAssertNil(summary.url)
        XCTAssertTrue(summary.isSummary)
    }
}
