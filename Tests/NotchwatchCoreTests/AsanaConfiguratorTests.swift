import Foundation
import XCTest
@testable import NotchwatchCore

final class AsanaConfiguratorTests: XCTestCase {
    private let sourceID = "asana-demo"

    private func layout(name: String, sections: [String], fields: [AsanaCustomField] = []) -> AsanaProjectLayout {
        AsanaProjectLayout(
            project: AsanaProject(gid: "p1", name: name),
            sections: sections.enumerated().map { AsanaSection(gid: "s\($0.offset + 1)", name: $0.element) },
            fields: fields
        )
    }

    private func enumField(_ gid: String, _ name: String, _ options: [(String, String)]) -> AsanaCustomField {
        AsanaCustomField(gid: gid, name: name, type: "enum", options: options.map { .init(gid: $0.0, name: $0.1) })
    }

    private func textField(_ gid: String, _ name: String) -> AsanaCustomField {
        AsanaCustomField(gid: gid, name: name, type: "text")
    }

    // MARK: - Nombres en español

    func testSpanishLayout() {
        let layout = layout(
            name: "Mi TBC Incidencias",
            sections: ["Features", "Incidencias Detectadas", "Verificación", "Solución"],
            fields: [
                enumField("f-pri", "Prioridad", [
                    ("o-urg", "Incidencia (urgente)"), ("o-alta", "Prioridad Alta"), ("o-media", "Media"), ("o-baja", "Baja"),
                ]),
                enumField("f-est", "Estado", [("o-curso", "En curso"), ("o-bloq", "Bloqueada")]),
                textField("f-rep", "Reportado por"),
                textField("f-mod", "Módulo"),
            ]
        )

        let config = AsanaConfigurator.suggest(for: layout, sourceID: sourceID)

        XCTAssertEqual(config.collection.id, "asana-demo/mi-tbc")
        XCTAssertEqual(config.collection.name, "Mi TBC")
        XCTAssertTrue(config.collection.enabled)
        XCTAssertEqual(config.projectGid, "p1")
        XCTAssertEqual(config.projectName, "Mi TBC Incidencias")
        XCTAssertEqual(config.detectedSectionGid, "s2")
        XCTAssertEqual(config.resolvedSectionGid, "s3")
        XCTAssertEqual(config.priorityField, PriorityField(fieldGid: "f-pri", options: [
            .urgente: "o-urg", .alta: "o-alta", .media: "o-media", .baja: "o-baja",
        ]))
        XCTAssertEqual(config.statusField, StatusField(fieldGid: "f-est", inProgressOptionGid: "o-curso"))
        XCTAssertEqual(config.reporterFieldGid, "f-rep")
        XCTAssertEqual(config.moduleFieldGid, "f-mod")
    }

    // MARK: - Nombres en inglés

    func testEnglishLayout() {
        let layout = layout(
            name: "Billing Incidents",
            sections: ["Backlog", "In review", "Done"],
            fields: [
                enumField("f-pri", "Priority", [("o-low", "Low"), ("o-med", "Medium"), ("o-high", "High"), ("o-crit", "Critical")]),
                enumField("f-st", "Status", [("o-todo", "To do"), ("o-doing", "In progress")]),
                textField("f-rep", "Reporter"),
                textField("f-mod", "Module"),
            ]
        )

        let config = AsanaConfigurator.suggest(for: layout, sourceID: sourceID)

        XCTAssertEqual(config.collection.id, "asana-demo/billing")
        XCTAssertEqual(config.collection.name, "Billing")
        XCTAssertEqual(config.detectedSectionGid, "s1")
        XCTAssertEqual(config.resolvedSectionGid, "s3")
        XCTAssertEqual(config.priorityField?.options, [.baja: "o-low", .media: "o-med", .alta: "o-high", .urgente: "o-crit"])
        XCTAssertEqual(config.statusField, StatusField(fieldGid: "f-st", inProgressOptionGid: "o-doing"))
        XCTAssertEqual(config.reporterFieldGid, "f-rep")
        XCTAssertEqual(config.moduleFieldGid, "f-mod")
    }

    // MARK: - Sin coincidencias

    func testNothingMatchingFallsBackToFirstSection() {
        let layout = layout(
            name: "Soporte",
            sections: ["Entrada", "Trabajando", "Cerrado"],
            fields: [
                enumField("f-x", "Tipo", [("o-1", "Bug")]),
                textField("f-y", "Cliente"),
                // Un campo de prioridad que no es enum no sirve.
                textField("f-z", "Prioridad"),
            ]
        )

        let config = AsanaConfigurator.suggest(for: layout, sourceID: sourceID)

        XCTAssertEqual(config.collection.name, "Soporte")
        XCTAssertEqual(config.detectedSectionGid, "s1")
        XCTAssertNil(config.resolvedSectionGid)
        XCTAssertNil(config.priorityField)
        XCTAssertNil(config.statusField)
        XCTAssertNil(config.reporterFieldGid)
        XCTAssertNil(config.moduleFieldGid)
    }

    func testProjectWithoutSectionsHasEmptyDetectedSection() {
        let config = AsanaConfigurator.suggest(for: layout(name: "Vacío", sections: []), sourceID: sourceID)
        XCTAssertEqual(config.detectedSectionGid, "")
        XCTAssertNil(config.resolvedSectionGid)
    }

    func testStatusFieldWithoutInProgressOptionIsIgnored() {
        let layout = layout(
            name: "X",
            sections: ["Detectadas"],
            fields: [enumField("f-est", "Estado", [("o-1", "Abierta"), ("o-2", "Cerrada")])]
        )
        XCTAssertNil(AsanaConfigurator.suggest(for: layout, sourceID: sourceID).statusField)
    }

    func testFirstMatchingOptionWinsPerPriority() {
        let layout = layout(
            name: "X",
            sections: ["Detectadas"],
            fields: [enumField("f-pri", "Prioridad", [("o-1", "Alta"), ("o-2", "Muy alta"), ("o-3", "Sin clasificar")])]
        )
        XCTAssertEqual(AsanaConfigurator.suggest(for: layout, sourceID: sourceID).priorityField?.options, [.alta: "o-1"])
    }

    // MARK: - Slug

    func testSlug() {
        XCTAssertEqual(AsanaConfigurator.slug("Mi TBC Incidencias"), "mi-tbc")
        XCTAssertEqual(AsanaConfigurator.slug("Operaciones Incidencias"), "operaciones")
        XCTAssertEqual(AsanaConfigurator.slug("Finanzas"), "finanzas")
        XCTAssertEqual(AsanaConfigurator.slug("Atención al Cliente — 2026"), "atencion-al-cliente-2026")
        XCTAssertEqual(AsanaConfigurator.slug("  Incidencias  "), "incidencias")
        XCTAssertEqual(AsanaConfigurator.slug("Billing Incidents"), "billing")
    }

    // MARK: - Estilo

    func testStyleIsStableAcrossCallsAndComesFromTheFixedList() {
        let first = AsanaConfigurator.suggest(for: layout(name: "Ventas Incidencias", sections: ["A"]), sourceID: sourceID)
        let second = AsanaConfigurator.suggest(for: layout(name: "Ventas Incidencias", sections: ["A"]), sourceID: "otra")

        XCTAssertEqual(first.collection.style, second.collection.style)
        XCTAssertTrue(AsanaConfigurator.styles.contains(first.collection.style))
        XCTAssertEqual(AsanaConfigurator.styles.count, 8)
        XCTAssertEqual(Set(AsanaConfigurator.styles.map(\.symbol)).count, 8)
    }

    func testStyleDistributesDifferentNames() {
        let names = ["Ventas", "Finanzas", "Operaciones", "Traslados", "Mailing", "Mi TBC", "TBC", "Soporte", "Marketing"]
        let styles = Set(names.map { AsanaConfigurator.style(forName: $0) })
        XCTAssertGreaterThan(styles.count, 1)
    }
}
