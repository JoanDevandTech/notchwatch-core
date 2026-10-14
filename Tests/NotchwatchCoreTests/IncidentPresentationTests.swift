import Foundation
import XCTest
@testable import NotchwatchCore

final class IncidentPresentationTests: XCTestCase {
    private let now = isoDate("2026-10-14T10:00:00Z")

    /// Incidencia con el asignado indicado.
    private func assigned(gid: String?, name: String?) -> Incident {
        var incident = sampleIncident("a", createdAt: now)
        incident.assigneeGid = gid
        incident.assigneeName = name
        return incident
    }

    // MARK: - appLabel

    func testAppLabelMapsEveryKnownProject() {
        let expected: [(key: String, label: String)] = [
            ("ventas", "Ventas"),
            ("finanzas", "Finanzas"),
            ("operaciones", "Operaciones"),
            ("traslados", "Traslados"),
            ("mailing", "Mailing"),
            ("mitbc", "Mi TBC"),
            ("general", "TBC"),
        ]
        for (key, label) in expected {
            XCTAssertEqual(sampleIncident("a", createdAt: now, projectKey: key).appLabel, label, "clave \(key)")
        }
    }

    func testAppLabelFallsBackToProjectName() {
        let incident = Incident(
            gid: "a",
            projectKey: "soporte",
            projectName: "Soporte Incidencias",
            name: "Prueba",
            createdAt: now
        )
        XCTAssertEqual(incident.appLabel, "Soporte Incidencias")
    }

    func testEveryDefaultProjectHasShortLabel() {
        // Detecta claves de la config sin nombre corto (o con una errata en el switch).
        // Nombre centinela: algunos proyectos se llaman igual que su etiqueta ("Finanzas").
        let unmapped = "(sin etiqueta)"
        for project in NotchwatchConfig.tubuencamino.projects {
            let incident = Incident(
                gid: "a",
                projectKey: project.key,
                projectName: unmapped,
                name: "Prueba",
                createdAt: now
            )
            XCTAssertNotEqual(incident.appLabel, unmapped, "clave \(project.key)")
        }
    }

    // MARK: - isAssigned

    func testGidMatch() {
        let incident = assigned(gid: "111", name: "Ana López")
        XCTAssertTrue(incident.isAssigned(toUserGid: "111", name: "Ana López"))
        XCTAssertTrue(incident.isAssigned(toUserGid: "111", name: nil))
        // Con los dos GID, el nombre no cuenta.
        XCTAssertTrue(incident.isAssigned(toUserGid: "111", name: "Otra Persona"))
    }

    func testGidMismatchIsFalseEvenWithSameName() {
        let incident = assigned(gid: "111", name: "Ana López")
        XCTAssertFalse(incident.isAssigned(toUserGid: "222", name: "Ana López"))
    }

    func testWithoutIncidentGidComparesNamesIgnoringCaseAndSpaces() {
        let incident = assigned(gid: nil, name: "  Ana López ")
        XCTAssertTrue(incident.isAssigned(toUserGid: "111", name: "ana lópez"))
        XCTAssertTrue(incident.isAssigned(toUserGid: "111", name: "ANA LÓPEZ\n"))
        XCTAssertFalse(incident.isAssigned(toUserGid: "111", name: "Ana"))
    }

    func testWithoutUserGidComparesNames() {
        let incident = assigned(gid: "111", name: "Ana López")
        XCTAssertTrue(incident.isAssigned(toUserGid: nil, name: "ana lópez"))
        XCTAssertFalse(incident.isAssigned(toUserGid: nil, name: "Luis"))
    }

    func testEmptyStringsCountAsMissing() {
        // GID en blanco: se decide por nombre.
        XCTAssertTrue(assigned(gid: "  ", name: "Ana").isAssigned(toUserGid: "111", name: "ana"))
        XCTAssertTrue(assigned(gid: "111", name: "Ana").isAssigned(toUserGid: "", name: "Ana"))
        // Dos valores en blanco no son una coincidencia.
        XCTAssertFalse(assigned(gid: "", name: nil).isAssigned(toUserGid: "", name: nil))
        XCTAssertFalse(assigned(gid: nil, name: " ").isAssigned(toUserGid: nil, name: " "))
        XCTAssertFalse(assigned(gid: " ", name: "").isAssigned(toUserGid: "\n", name: "  "))
    }

    func testUnassignedIsFalse() {
        let incident = assigned(gid: nil, name: nil)
        XCTAssertFalse(incident.isAssigned(toUserGid: "111", name: "Ana López"))
    }

    func testNothingKnownIsFalse() {
        XCTAssertFalse(assigned(gid: nil, name: nil).isAssigned(toUserGid: nil, name: nil))
        XCTAssertFalse(assigned(gid: "111", name: "Ana").isAssigned(toUserGid: nil, name: nil))
        // GID en un lado y nombre en el otro: nada que comparar.
        XCTAssertFalse(assigned(gid: "111", name: nil).isAssigned(toUserGid: nil, name: "Ana"))
        XCTAssertFalse(assigned(gid: nil, name: "Ana").isAssigned(toUserGid: "111", name: nil))
    }
}
