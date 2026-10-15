import Foundation
import XCTest
@testable import NotchwatchCore

final class NotificationPlannerTests: XCTestCase {
    private let now = isoDate("2026-10-14T10:00:00Z")
    private let strings = NotificationStrings.spanish

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
        NotificationPlanner.payload(for: incident, strings: strings).subtitle
    }

    func testContractConstants() {
        XCTAssertEqual(NotificationPlanner.summaryIdentifier, "notchwatch.summary")
        XCTAssertEqual(NotificationPlanner.maxIndividual, 3)
    }

    // MARK: - Reparto individual / resumen

    func testEmptyInputPlansNothing() {
        XCTAssertEqual(NotificationPlanner.payloads(for: [], asBatch: false, strings: strings), [])
        XCTAssertEqual(NotificationPlanner.payloads(for: [], asBatch: true, strings: strings), [])
        XCTAssertNil(NotificationPlanner.summary(for: [], strings: strings))
    }

    func testSingleIncidentInBatchIsStillIndividual() {
        let incident = sampleIncident("a", priority: .alta, createdAt: now)

        let payloads = NotificationPlanner.payloads(for: [incident], asBatch: true, strings: strings)

        XCTAssertEqual(payloads, [NotificationPlanner.payload(for: incident, strings: strings)])
        XCTAssertEqual(payloads.first?.isSummary, false)
        XCTAssertEqual(payloads.first?.identifier, "a")
    }

    func testTwoIncidentsAreIndividualSortedByPriority() {
        let lowRecent = sampleIncident("baja-nueva", priority: .baja, createdAt: now)
        let highOld = sampleIncident("alta-vieja", priority: .alta, createdAt: now.addingTimeInterval(-3600))

        let payloads = NotificationPlanner.payloads(for: [lowRecent, highOld], asBatch: false, strings: strings)

        XCTAssertEqual(payloads.map(\.identifier), ["alta-vieja", "baja-nueva"])
        XCTAssertEqual(payloads.map(\.incidentGid), ["alta-vieja", "baja-nueva"])
        XCTAssertEqual(payloads.map(\.isSummary), [false, false])
    }

    func testSamePriorityNewestFirst() {
        let old = sampleIncident("vieja", priority: .media, createdAt: now.addingTimeInterval(-600))
        let recent = sampleIncident("nueva", priority: .media, createdAt: now)

        let payloads = NotificationPlanner.payloads(for: [old, recent], asBatch: false, strings: strings)

        XCTAssertEqual(payloads.map(\.identifier), ["nueva", "vieja"])
    }

    func testUpToMaxIndividualStaysIndividual() {
        let incidents = (1...NotificationPlanner.maxIndividual).map { index in
            sampleIncident("i\(index)", createdAt: now.addingTimeInterval(-Double(index)))
        }

        let payloads = NotificationPlanner.payloads(for: incidents.reversed(), asBatch: false, strings: strings)

        XCTAssertEqual(payloads.map(\.identifier), ["i1", "i2", "i3"])
    }

    func testMoreThanMaxIndividualCollapsesIntoSummary() throws {
        let incidents = [
            sampleIncident("baja", priority: .baja, createdAt: now),
            sampleIncident("urgente", priority: .urgente, createdAt: now.addingTimeInterval(-7200)),
            sampleIncident("media", priority: .media, createdAt: now),
            sampleIncident("alta", priority: .alta, createdAt: now),
        ]

        let payloads = NotificationPlanner.payloads(for: incidents, asBatch: false, strings: strings)

        let summary = try XCTUnwrap(NotificationPlanner.summary(for: incidents, strings: strings))
        XCTAssertEqual(payloads, [summary])
        XCTAssertTrue(summary.isSummary)
        XCTAssertEqual(summary.title, "4 incidencias nuevas")
        XCTAssertEqual(summary.body, "Incidencia urgente y 3 más")
    }

    func testBatchOfTwoIsSummary() throws {
        let incidents = [
            sampleIncident("a", priority: .media, createdAt: now),
            sampleIncident("b", priority: .alta, createdAt: now.addingTimeInterval(-60), collectionKey: "finanzas"),
        ]

        let payloads = NotificationPlanner.payloads(for: incidents, asBatch: true, strings: strings)

        let summary = try XCTUnwrap(NotificationPlanner.summary(for: incidents, pendingAtStartup: true, strings: strings))
        XCTAssertEqual(payloads, [summary])
        // La tanda del arranque son las que ya estaban pendientes, no nuevas.
        XCTAssertEqual(summary.title, "2 incidencias pendientes")
        XCTAssertEqual(summary.subtitle, "La más importante: Alta · Finanzas")
        XCTAssertEqual(summary.body, "Incidencia b y 1 más")
    }

    // MARK: - Notificación individual

    func testTitleCombinesPriorityAndCollection() {
        let urgent = sampleIncident("a", priority: .urgente, createdAt: now, collectionKey: "finanzas")
        let unprioritized = sampleIncident("b", priority: .ninguna, createdAt: now, collectionKey: "ventas")

        XCTAssertEqual(NotificationPlanner.payload(for: urgent, strings: strings).title, "Urgente · Finanzas")
        XCTAssertEqual(NotificationPlanner.payload(for: unprioritized, strings: strings).title, "Sin prioridad · Ventas")
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
        var incident = sampleIncident("1211000000000001", priority: .alta, createdAt: now, collectionKey: "traslados")
        incident.name = "No se asigna conductor"
        incident.permalinkURL = url

        XCTAssertEqual(
            NotificationPlanner.payload(for: incident, strings: strings),
            NotificationPayload(
                identifier: "1211000000000001",
                title: "Alta · Traslados",
                subtitle: "",
                body: "No se asigna conductor",
                threadIdentifier: tbcCollectionID("traslados"),
                incidentGid: "1211000000000001",
                url: url,
                isSummary: false
            )
        )
    }

    func testIndividualPayloadWithoutLinkHasNilURL() {
        let payload = NotificationPlanner.payload(for: sampleIncident("a", createdAt: now), strings: strings)
        XCTAssertNil(payload.url)
        XCTAssertEqual(payload.incidentGid, "a")
    }

    // MARK: - Resumen

    func testSummaryOfThreeHighlightsTheMostImportant() throws {
        let earlier = now.addingTimeInterval(-3600)
        var newestUrgent = sampleIncident("urgente-nueva", priority: .urgente, createdAt: now, collectionKey: "mitbc")
        // El resumen no hereda el enlace de la más importante.
        newestUrgent.permalinkURL = try XCTUnwrap(URL(string: "https://app.asana.com/0/1/2"))
        let incidents = [
            sampleIncident("media", priority: .media, createdAt: now),
            sampleIncident("urgente-vieja", priority: .urgente, createdAt: earlier, collectionKey: "finanzas"),
            newestUrgent,
        ]

        let summary = try XCTUnwrap(NotificationPlanner.summary(for: incidents, strings: strings))

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
        // Con asBatch (arranque) se resume igual, pero como pendientes.
        var startup = summary
        startup.title = "3 incidencias pendientes"
        XCTAssertEqual(NotificationPlanner.payloads(for: incidents, asBatch: true, strings: strings), [startup])
    }

    func testSummaryOfOne() throws {
        var incident = sampleIncident("a", priority: .baja, createdAt: now, collectionKey: "general")
        incident.permalinkURL = URL(string: "https://app.asana.com/0/1/2")

        let summary = try XCTUnwrap(NotificationPlanner.summary(for: [incident], strings: strings))

        XCTAssertEqual(summary.title, "1 incidencia nueva")
        XCTAssertEqual(summary.subtitle, "La más importante: Baja · TBC")
        XCTAssertEqual(summary.body, "Incidencia a")
        XCTAssertEqual(summary.identifier, "notchwatch.summary")
        XCTAssertEqual(summary.threadIdentifier, "notchwatch.summary")
        XCTAssertNil(summary.incidentGid)
        XCTAssertNil(summary.url)
        XCTAssertTrue(summary.isSummary)
    }

    func testStartupSummaryOfOneSaysPending() throws {
        let incident = sampleIncident("a", priority: .alta, createdAt: now)

        let summary = try XCTUnwrap(NotificationPlanner.summary(for: [incident], pendingAtStartup: true, strings: strings))

        XCTAssertEqual(summary.title, "1 incidencia pendiente")
    }

    // MARK: - Textos inyectados

    func testUsesInjectedStrings() throws {
        let english = NotificationStrings(
            priorityLabel: { $0 == .urgente ? "Urgent" : "Other" },
            reportedBy: { "Reported by \($0)" },
            consoleErrors: { "\($0) console errors" },
            newIncidents: { "\($0) new incidents" },
            pendingIncidents: { "\($0) pending incidents" },
            mostImportant: { "Top: \($0)" },
            andMore: { "\($0) and \($1) more" }
        )
        var urgent = sampleIncident("u", priority: .urgente, createdAt: now, collectionKey: "finanzas")
        urgent.reporter = "Ana"
        urgent.consoleErrors = 2
        let other = sampleIncident("o", priority: .baja, createdAt: now)

        let payload = NotificationPlanner.payload(for: urgent, strings: english)
        XCTAssertEqual(payload.title, "Urgent · Finanzas")
        XCTAssertEqual(payload.subtitle, "Reported by Ana · 2 console errors")

        let summary = try XCTUnwrap(NotificationPlanner.summary(for: [other, urgent], strings: english))
        XCTAssertEqual(summary.title, "2 new incidents")
        XCTAssertEqual(summary.subtitle, "Top: Urgent · Finanzas")
        XCTAssertEqual(summary.body, "Incidencia u and 1 more")

        let startup = try XCTUnwrap(NotificationPlanner.summary(for: [other], pendingAtStartup: true, strings: english))
        XCTAssertEqual(startup.title, "1 pending incidents")
        XCTAssertEqual(startup.body, "Incidencia o")
    }
}
