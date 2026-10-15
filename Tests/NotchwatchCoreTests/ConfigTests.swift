import Foundation
import XCTest
@testable import NotchwatchCore

final class ConfigTests: XCTestCase {
    func testDefaultConfigHasSevenProjectsInOrder() {
        let config = NotchwatchConfig.tubuencamino
        XCTAssertEqual(
            config.projects.map(\.key),
            ["ventas", "finanzas", "operaciones", "traslados", "mailing", "mitbc", "general"]
        )
        XCTAssertEqual(config.projects.map(\.id), config.projects.map(\.key))
        XCTAssertTrue(config.projects.allSatisfy(\.enabled))
        XCTAssertEqual(config.estadoFieldGid, "1214163825159804")
        XCTAssertEqual(config.estadoEnCursoOptionGid, "1214163825159805")
        XCTAssertEqual(config.pollInterval, 20)
    }

    func testProjectNamesAndGids() throws {
        XCTAssertEqual(try defaultProject("ventas").name, "Ventas Incidencias")
        XCTAssertEqual(try defaultProject("ventas").projectGid, "1216898612014391")
        XCTAssertEqual(try defaultProject("finanzas").name, "Finanzas")
        XCTAssertEqual(try defaultProject("mitbc").projectGid, "1219500159228408")
        XCTAssertEqual(try defaultProject("general").name, "TBC Incidencias")
        XCTAssertEqual(try defaultProject("general").projectGid, "1214164017398876")
    }

    func testGlobalPriorityFieldInSixProjects() throws {
        let config = NotchwatchConfig.tubuencamino
        let expected: [IncidentPriority: String] = [
            .baja: "1219502866938805",
            .media: "1219502866938806",
            .urgente: "1219502866938807", // "Incidencia"
            .alta: "1219502866938808", // "Prioridad Alta"
        ]
        for project in config.projects where project.key != "general" {
            XCTAssertEqual(project.priorityField.fieldGid, "1219502866938804", project.key)
            XCTAssertEqual(project.priorityField.options, expected, project.key)
        }
        let ventas = try defaultProject("ventas")
        XCTAssertEqual(ventas.priorityField.priority(forOptionGid: "1219502866938807"), .urgente)
        XCTAssertEqual(ventas.priorityField.priority(forOptionGid: "1219502866938808"), .alta)
        XCTAssertEqual(ventas.priorityField.priority(forOptionGid: nil), .ninguna)
        XCTAssertEqual(ventas.priorityField.priority(forOptionGid: ""), .ninguna)
        XCTAssertEqual(ventas.priorityField.priority(forOptionGid: "999"), .ninguna)
        // Una opción del campo local no vale en el global.
        XCTAssertEqual(ventas.priorityField.priority(forOptionGid: "1214163825159879"), .ninguna)
    }

    func testLocalPriorityFieldInTBCIncidencias() throws {
        let general = try defaultProject("general")
        XCTAssertEqual(general.priorityField.fieldGid, "1214164017398881")
        XCTAssertEqual(general.priorityField.options, [
            .baja: "1214164017398882",
            .media: "1214164017398883",
            .urgente: "1214164017398884",
            .alta: "1214163825159879",
        ])
        XCTAssertEqual(general.priorityField.priority(forOptionGid: "1214163825159879"), .alta)
        XCTAssertEqual(general.priorityField.priority(forOptionGid: "1219502866938808"), .ninguna)
    }

    func testAllSectionGidsAreUnique() throws {
        let config = NotchwatchConfig.tubuencamino
        var gids: [String] = []
        for project in config.projects {
            let s = project.sections
            gids += [
                s.features, s.detectadas, s.verificacion, s.solucion,
                s.validacion, s.seguimientoInicial, s.seguimientoSemana, s.historico,
            ]
        }
        XCTAssertEqual(gids.count, 56)
        XCTAssertEqual(Set(gids).count, 56)
        XCTAssertEqual(try defaultProject("ventas").sections.detectadas, "1219500158564901")
        XCTAssertEqual(try defaultProject("ventas").sections.verificacion, "1219499888926675")
        XCTAssertEqual(try defaultProject("mitbc").sections.seguimientoSemana, "1219515631339719")
        XCTAssertEqual(try defaultProject("general").sections.detectadas, "1214164017398877")
        XCTAssertEqual(try defaultProject("general").sections.verificacion, "1214164017398879")
    }

    func testPriorityMapEncodesAsJSONObject() throws {
        let field = try defaultProject("general").priorityField
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

    func testConfigCodableRoundTrip() throws {
        var config = NotchwatchConfig.tubuencamino
        config.pollInterval = 45
        config.projects[2].enabled = false

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(NotchwatchConfig.self, from: data)

        XCTAssertEqual(decoded.projects, config.projects)
        XCTAssertEqual(decoded.estadoFieldGid, config.estadoFieldGid)
        XCTAssertEqual(decoded.estadoEnCursoOptionGid, config.estadoEnCursoOptionGid)
        XCTAssertEqual(decoded.pollInterval, 45)
        XCTAssertFalse(decoded.projects[2].enabled)
    }

    func testIncidentCodableRoundTrip() throws {
        let incident = Incident(
            gid: "1",
            projectKey: "ventas",
            projectName: "Ventas Incidencias",
            name: "Prueba",
            priority: .alta,
            reporter: "María",
            module: "Presupuestos",
            consoleErrors: 3,
            createdAt: isoDate("2026-10-14T08:00:00Z"),
            dueOn: "2026-10-20",
            assigneeName: "Joan",
            permalinkURL: URL(string: "https://app.asana.com/0/1/1")
        )
        let data = try JSONEncoder().encode(incident)
        XCTAssertEqual(try JSONDecoder().decode(Incident.self, from: data), incident)
        XCTAssertEqual(incident.id, "1")
    }
}
