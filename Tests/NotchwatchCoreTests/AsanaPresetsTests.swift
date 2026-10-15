import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NotchwatchCore

final class AsanaPresetsTests: XCTestCase {
    private let keys = ["ventas", "finanzas", "operaciones", "traslados", "mailing", "mitbc", "general"]

    func testSevenProjectsInOrderWithUniqueIDs() {
        let preset = AsanaPresets.tubuencamino
        XCTAssertEqual(preset.id, "asana-tubuencamino")
        XCTAssertEqual(preset.displayName, "Tubuencamino")
        XCTAssertEqual(preset.projects.map(\.id), keys.map { "asana-tubuencamino/\($0)" })
        XCTAssertEqual(Set(preset.projects.map(\.id)).count, 7)
        XCTAssertEqual(Set(preset.projects.map(\.projectGid)).count, 7)
        XCTAssertTrue(preset.projects.allSatisfy { $0.collection.enabled })
    }

    func testCollectionNamesAndStyles() throws {
        XCTAssertEqual(AsanaPresets.tubuencamino.projects.map(\.collection.name), [
            "Ventas", "Finanzas", "Operaciones", "Traslados", "Mailing", "Mi TBC", "TBC",
        ])
        XCTAssertEqual(AsanaPresets.tubuencamino.projects.map(\.collection.style.symbol), [
            "chart.bar.fill", "creditcard.fill", "shippingbox.fill", "car.fill", "envelope.fill",
            "person.crop.circle.fill", "flame.fill",
        ])
        XCTAssertEqual(try presetProject("ventas").collection.style.colorHex, "#DFB47D")
        XCTAssertEqual(try presetProject("operaciones").collection.style.colorHex, "#85BAA8")
        XCTAssertEqual(try presetProject("general").collection.style.colorHex, "#E78580")
    }

    func testProjectNamesAndGids() throws {
        XCTAssertEqual(try presetProject("ventas").projectName, "Ventas Incidencias")
        XCTAssertEqual(try presetProject("ventas").projectGid, "1216898612014391")
        XCTAssertEqual(try presetProject("finanzas").projectName, "Finanzas")
        XCTAssertEqual(try presetProject("mitbc").projectGid, "1219500159228408")
        XCTAssertEqual(try presetProject("general").projectName, "TBC Incidencias")
        XCTAssertEqual(try presetProject("general").projectGid, "1214164017398876")
    }

    func testEveryProjectHasSectionsStatusAndTextFields() {
        for project in AsanaPresets.tubuencamino.projects {
            XCTAssertFalse(project.detectedSectionGid.isEmpty, project.id)
            XCTAssertNotNil(project.resolvedSectionGid, project.id)
            XCTAssertNotNil(project.priorityField, project.id)
            XCTAssertEqual(project.statusField, StatusField(fieldGid: "1214163825159804", inProgressOptionGid: "1214163825159805", solvedOptionGid: "1214163825159829"), project.id)
            XCTAssertEqual(project.reporterFieldGid, "1216067243827070", project.id)
            XCTAssertEqual(project.moduleFieldGid, "1216067230748421", project.id)
        }
    }

    func testPresetOffersStartProgressWithAllProjectsEnabled() {
        let source = AsanaSource(config: AsanaPresets.tubuencamino, token: "tok", transport: MockTransport { _ in MockResponse() })
        XCTAssertTrue(source.capabilities.contains(.startProgress))
    }

    func testSectionGidsAreUnique() throws {
        var gids: [String] = []
        for project in AsanaPresets.tubuencamino.projects {
            gids.append(project.detectedSectionGid)
            gids.append(try XCTUnwrap(project.resolvedSectionGid))
        }
        XCTAssertEqual(gids.count, 14)
        XCTAssertEqual(Set(gids).count, 14)
        XCTAssertEqual(try presetProject("ventas").detectedSectionGid, "1219500158564901")
        XCTAssertEqual(try presetProject("ventas").resolvedSectionGid, "1219499888926675")
        XCTAssertEqual(try presetProject("general").detectedSectionGid, "1214164017398877")
        XCTAssertEqual(try presetProject("general").resolvedSectionGid, "1214164017398879")
    }

    func testGlobalPriorityFieldInSixProjects() throws {
        let expected: [IncidentPriority: String] = [
            .baja: "1219502866938805",
            .media: "1219502866938806",
            .urgente: "1219502866938807",
            .alta: "1219502866938808",
        ]
        for project in AsanaPresets.tubuencamino.projects where project.id != tbcCollectionID("general") {
            XCTAssertEqual(project.priorityField?.fieldGid, "1219502866938804", project.id)
            XCTAssertEqual(project.priorityField?.options, expected, project.id)
        }
        let field = try XCTUnwrap(try presetProject("ventas").priorityField)
        XCTAssertEqual(field.priority(forOptionGid: "1219502866938807"), .urgente)
        XCTAssertEqual(field.priority(forOptionGid: "1219502866938808"), .alta)
        XCTAssertEqual(field.priority(forOptionGid: nil), .ninguna)
        XCTAssertEqual(field.priority(forOptionGid: ""), .ninguna)
        XCTAssertEqual(field.priority(forOptionGid: "999"), .ninguna)
        // Una opción del campo local no vale en el global.
        XCTAssertEqual(field.priority(forOptionGid: "1214163825159879"), .ninguna)
    }

    func testLocalPriorityFieldInTBCIncidencias() throws {
        let field = try XCTUnwrap(try presetProject("general").priorityField)
        XCTAssertEqual(field.fieldGid, "1214164017398881")
        XCTAssertEqual(field.options, [
            .baja: "1214164017398882",
            .media: "1214164017398883",
            .urgente: "1214164017398884",
            .alta: "1214163825159879",
        ])
        XCTAssertEqual(field.priority(forOptionGid: "1214163825159879"), .alta)
        XCTAssertEqual(field.priority(forOptionGid: "1219502866938808"), .ninguna)
    }

    func testPresetMatchesConfiguratorSlugs() {
        for project in AsanaPresets.tubuencamino.projects {
            let expected = WatchedCollection.makeID(
                sourceID: AsanaPresets.tubuencaminoSourceID,
                key: AsanaConfigurator.slug(project.projectName)
            )
            // La clave corta del preajuste («mitbc», «general») es una decisión propia; el resto coincide.
            if project.id != tbcCollectionID("mitbc") && project.id != tbcCollectionID("general") {
                XCTAssertEqual(project.id, expected)
            }
        }
    }

    // MARK: - Codable

    func testPriorityMapEncodesAsJSONObject() throws {
        let field = try XCTUnwrap(try presetProject("general").priorityField)
        let data = try JSONEncoder().encode(field)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["fieldGid"] as? String, "1214164017398881")
        let options = try XCTUnwrap(object["options"] as? [String: String])
        XCTAssertEqual(options, [
            "baja": "1214164017398882",
            "media": "1214164017398883",
            "urgente": "1214164017398884",
            "alta": "1214163825159879",
        ])
    }

    func testPriorityMapDecodesFromJSONObject() throws {
        let json = #"{"fieldGid":"1","options":{"alta":"10","urgente":"20","ninguna":"30"}}"#
        let field = try JSONDecoder().decode(PriorityField.self, from: Data(json.utf8))

        XCTAssertEqual(field.fieldGid, "1")
        XCTAssertEqual(field.options, [.alta: "10", .urgente: "20", .ninguna: "30"])
        XCTAssertEqual(field.priority(forOptionGid: "20"), .urgente)
    }

    func testSourceConfigCodableRoundTrip() throws {
        var config = AsanaPresets.tubuencamino
        config.projects[2].collection.enabled = false
        config.projects[3].resolvedSectionGid = nil

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AsanaSourceConfig.self, from: data)

        XCTAssertEqual(decoded, config)
        XCTAssertFalse(decoded.projects[2].collection.enabled)
        XCTAssertNil(decoded.projects[3].resolvedSectionGid)
    }

    func testIncidentCodableRoundTrip() throws {
        let incident = Incident(
            id: "1",
            collectionID: tbcCollectionID("ventas"),
            collectionName: "Ventas",
            name: "Prueba",
            priority: .alta,
            reporter: "María",
            module: "Presupuestos",
            consoleErrors: 3,
            createdAt: isoDate("2026-10-14T08:00:00Z"),
            dueOn: "2026-10-20",
            assigneeID: "u1",
            assigneeName: "Joan",
            permalinkURL: URL(string: "https://app.asana.com/0/1/1")
        )
        let data = try JSONEncoder().encode(incident)
        XCTAssertEqual(try JSONDecoder().decode(Incident.self, from: data), incident)
    }
}
