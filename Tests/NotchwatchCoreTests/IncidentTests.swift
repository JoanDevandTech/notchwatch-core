import Foundation
import XCTest
@testable import NotchwatchCore

final class IncidentTests: XCTestCase {
    private let now = isoDate("2026-10-14T10:00:00Z")

    /// Incidencia con el asignado indicado.
    private func assigned(id: String?, name: String?) -> Incident {
        var incident = sampleIncident("a", createdAt: now)
        incident.assigneeID = id
        incident.assigneeName = name
        return incident
    }

    // MARK: - isAssigned

    func testIDMatch() {
        let incident = assigned(id: "111", name: "Ana López")
        XCTAssertTrue(incident.isAssigned(toUserID: "111", name: "Ana López"))
        XCTAssertTrue(incident.isAssigned(toUserID: "111", name: nil))
        // Con los dos identificadores, el nombre no cuenta.
        XCTAssertTrue(incident.isAssigned(toUserID: "111", name: "Otra Persona"))
    }

    func testIDMismatchIsFalseEvenWithSameName() {
        let incident = assigned(id: "111", name: "Ana López")
        XCTAssertFalse(incident.isAssigned(toUserID: "222", name: "Ana López"))
    }

    func testWithoutIncidentIDComparesNamesIgnoringCaseAndSpaces() {
        let incident = assigned(id: nil, name: "  Ana López ")
        XCTAssertTrue(incident.isAssigned(toUserID: "111", name: "ana lópez"))
        XCTAssertTrue(incident.isAssigned(toUserID: "111", name: "ANA LÓPEZ\n"))
        XCTAssertFalse(incident.isAssigned(toUserID: "111", name: "Ana"))
    }

    func testWithoutUserIDComparesNames() {
        let incident = assigned(id: "111", name: "Ana López")
        XCTAssertTrue(incident.isAssigned(toUserID: nil, name: "ana lópez"))
        XCTAssertFalse(incident.isAssigned(toUserID: nil, name: "Luis"))
    }

    func testEmptyStringsCountAsMissing() {
        // Identificador en blanco: se decide por nombre.
        XCTAssertTrue(assigned(id: "  ", name: "Ana").isAssigned(toUserID: "111", name: "ana"))
        XCTAssertTrue(assigned(id: "111", name: "Ana").isAssigned(toUserID: "", name: "Ana"))
        // Dos valores en blanco no son una coincidencia.
        XCTAssertFalse(assigned(id: "", name: nil).isAssigned(toUserID: "", name: nil))
        XCTAssertFalse(assigned(id: nil, name: " ").isAssigned(toUserID: nil, name: " "))
        XCTAssertFalse(assigned(id: " ", name: "").isAssigned(toUserID: "\n", name: "  "))
    }

    func testUnassignedIsFalse() {
        let incident = assigned(id: nil, name: nil)
        XCTAssertFalse(incident.isAssigned(toUserID: "111", name: "Ana López"))
    }

    func testNothingKnownIsFalse() {
        XCTAssertFalse(assigned(id: nil, name: nil).isAssigned(toUserID: nil, name: nil))
        XCTAssertFalse(assigned(id: "111", name: "Ana").isAssigned(toUserID: nil, name: nil))
        // Identificador en un lado y nombre en el otro: nada que comparar.
        XCTAssertFalse(assigned(id: "111", name: nil).isAssigned(toUserID: nil, name: "Ana"))
        XCTAssertFalse(assigned(id: nil, name: "Ana").isAssigned(toUserID: "111", name: nil))
    }

    // MARK: - Varios

    func testTextNonEmpty() {
        XCTAssertNil(Text.nonEmpty(nil))
        XCTAssertNil(Text.nonEmpty(""))
        XCTAssertNil(Text.nonEmpty(" \n\t"))
        XCTAssertEqual(Text.nonEmpty("  hola "), "hola")
    }

    func testIncidentActionRequiredCapabilities() {
        XCTAssertEqual(IncidentAction.assignToMe.requiredCapability, .assignToMe)
        XCTAssertEqual(IncidentAction.startProgress.requiredCapability, .startProgress)
        XCTAssertEqual(IncidentAction.resolve.requiredCapability, .resolve)
        XCTAssertEqual(IncidentAction.setDueDate("2026-10-20").requiredCapability, .dueDate)
        XCTAssertEqual(IncidentAction.setPriority(.alta).requiredCapability, .priority)
    }

    func testWatchedCollectionMakeID() {
        XCTAssertEqual(WatchedCollection.makeID(sourceID: "asana-x", key: "ventas"), "asana-x/ventas")
        let collection = WatchedCollection(id: "a/b", name: "B")
        XCTAssertTrue(collection.enabled)
        XCTAssertEqual(collection.style, .default)
    }
}
