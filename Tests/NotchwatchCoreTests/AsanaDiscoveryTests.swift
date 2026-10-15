import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NotchwatchCore

final class AsanaDiscoveryTests: XCTestCase {
    private let projectsOffset = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.cHJveWVjdG9z"

    /// Transporte que sirve cada endpoint de descubrimiento por su ruta.
    private func discoveryTransport() throws -> MockTransport {
        let workspaces = try fixture("workspaces")
        let projects1 = try fixture("projects_page1")
        let projects2 = try fixture("projects_page2")
        let sections = try fixture("sections")
        let fields = try fixture("custom_field_settings")
        let offset = projectsOffset
        return MockTransport { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/workspaces") { return MockResponse(body: workspaces) }
            if path.hasSuffix("/projects") {
                return MockResponse(body: queryValue(request, "offset") == offset ? projects2 : projects1)
            }
            if path.hasSuffix("/sections") { return MockResponse(body: sections) }
            if path.hasSuffix("/custom_field_settings") { return MockResponse(body: fields) }
            return MockResponse(status: 404, body: Data(#"{"errors":[{"message":"Not Found"}]}"#.utf8))
        }
    }

    func testWorkspaces() async throws {
        let transport = try discoveryTransport()
        let client = AsanaClient(token: "tok", transport: transport)

        let workspaces = try await client.workspaces()

        XCTAssertEqual(workspaces, [
            AsanaWorkspace(gid: "1199999999999999", name: "Tubuencamino"),
            AsanaWorkspace(gid: "1199999999999998", name: "Personal"),
        ])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/1.0/workspaces")
    }

    func testProjectsPaginateAndExcludeArchived() async throws {
        let transport = try discoveryTransport()
        let client = AsanaClient(token: "tok", transport: transport)

        let projects = try await client.projects(inWorkspace: "1199999999999999")

        XCTAssertEqual(projects.map(\.gid), ["1216898612014391", "1217141285197084", "1214164017398876"])
        XCTAssertEqual(projects.map(\.name), ["Ventas Incidencias", "Finanzas", "TBC Incidencias"])
        XCTAssertTrue(projects.allSatisfy { !$0.archived })

        let requests = transport.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.url?.path, "/api/1.0/projects")
            XCTAssertEqual(queryValue(request, "workspace"), "1199999999999999")
            XCTAssertEqual(queryValue(request, "archived"), "false")
            XCTAssertEqual(queryValue(request, "opt_fields"), "name,archived")
            XCTAssertEqual(queryValue(request, "limit"), "100")
        }
        XCTAssertNil(queryValue(requests[0], "offset"))
        XCTAssertEqual(queryValue(requests[1], "offset"), projectsOffset)
    }

    func testSections() async throws {
        let transport = try discoveryTransport()
        let client = AsanaClient(token: "tok", transport: transport)

        let sections = try await client.sections(ofProject: "1216898612014391")

        XCTAssertEqual(sections.map(\.name), ["Features", "Incidencias Detectadas", "Verificación", "Solución"])
        XCTAssertEqual(sections[1].gid, "1219500158564901")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/1.0/projects/1216898612014391/sections")
    }

    func testCustomFieldsKeepOnlyEnabledOptions() async throws {
        let transport = try discoveryTransport()
        let client = AsanaClient(token: "tok", transport: transport)

        let fields = try await client.customFields(ofProject: "1216898612014391")

        XCTAssertEqual(fields.map(\.name), ["Prioridad", "Estado", "Reportado por", "Módulo"])
        XCTAssertEqual(fields.map(\.type), ["enum", "enum", "text", "text"])
        // La opción deshabilitada «Antigua» no se ofrece.
        XCTAssertEqual(fields[0].options.map(\.name), ["Baja", "Media", "Incidencia (urgente)", "Prioridad Alta"])
        XCTAssertEqual(fields[1].options.map(\.gid), ["1214163825159805", "1214163825159806"])
        XCTAssertTrue(fields[2].options.isEmpty)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/1.0/projects/1216898612014391/custom_field_settings")
        XCTAssertEqual(queryValue(request, "opt_fields"), AsanaClient.customFieldOptFields)
    }

    func testLayoutCombinesSectionsAndFields() async throws {
        let transport = try discoveryTransport()
        let client = AsanaClient(token: "tok", transport: transport)
        let project = AsanaProject(gid: "1216898612014391", name: "Ventas Incidencias")

        let layout = try await client.layout(of: project)

        XCTAssertEqual(layout.project, project)
        XCTAssertEqual(layout.sections.count, 4)
        XCTAssertEqual(layout.fields.count, 4)
        XCTAssertEqual(
            Set(transport.requests.compactMap { $0.url?.path }),
            ["/api/1.0/projects/1216898612014391/sections", "/api/1.0/projects/1216898612014391/custom_field_settings"]
        )
    }

    func testLayoutPropagatesErrors() async throws {
        let transport = MockTransport { _ in MockResponse(status: 401, body: Data("{}".utf8)) }
        let client = AsanaClient(token: "tok", transport: transport)

        do {
            _ = try await client.layout(of: AsanaProject(gid: "1", name: "X"))
            XCTFail("Debería lanzar .unauthorized")
        } catch let error as SourceError {
            XCTAssertEqual(error, .unauthorized)
        }
    }
}
