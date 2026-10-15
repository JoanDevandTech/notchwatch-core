import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NotchwatchCore

final class AsanaClientTests: XCTestCase {
    private let ventasDetectadas = "1219500158564901"
    private let generalDetectadas = "1214164017398877"
    private let page2Offset = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.cGFnZTI"
    private let expectedOptFields =
        "name,created_at,due_on,notes,permalink_url,completed,assignee.gid,assignee.name,custom_fields.gid,custom_fields.display_value,custom_fields.enum_value.gid"
    private let taskURL = "https://app.asana.com/api/1.0/tasks/1211000000000001"

    /// Incidencia sobre la que se lanzan las acciones.
    private let sample = Incident(
        id: "1211000000000001",
        collectionID: tbcCollectionID("ventas"),
        collectionName: "Ventas",
        name: "No carga el listado de presupuestos",
        priority: .media,
        createdAt: Date(timeIntervalSince1970: 1_790_000_000)
    )

    /// Incidencias abiertas del proyecto del preajuste indicado.
    private func openIncidents(_ client: AsanaClient, project key: String) async throws -> [Incident] {
        let project = try presetProject(key)
        return try await client.openIncidents(in: project, collection: project.collection)
    }

    /// Transporte que sirve las dos páginas de Ventas según el offset.
    private func ventasTransport() throws -> MockTransport {
        let page1 = try fixture("tasks_ventas_page1")
        let page2 = try fixture("tasks_ventas_page2")
        let offset = page2Offset
        return MockTransport { request in
            queryValue(request, "offset") == offset ? MockResponse(body: page2) : MockResponse(body: page1)
        }
    }

    /// Lo común a todas las acciones: método, URL exacta, cabeceras y cuerpo JSON exacto.
    private func assertAction(
        _ request: URLRequest?,
        method: String,
        url: String,
        body: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let request = try XCTUnwrap(request, file: file, line: line)
        XCTAssertEqual(request.httpMethod, method, file: file, line: line)
        XCTAssertEqual(request.url?.absoluteString, url, file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json", file: file, line: line)
        XCTAssertEqual(bodyString(request), body, file: file, line: line)
    }

    // MARK: - Lectura y parseo

    func testMeParsesUserAndSendsHeaders() async throws {
        let body = try fixture("me")
        let transport = MockTransport { _ in MockResponse(body: body) }
        let client = AsanaClient(token: "tok-123", transport: transport)

        let me = try await client.me()

        XCTAssertEqual(me.userID, "1200000000000001")
        XCTAssertEqual(me.name, "Joan Torres")
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/1.0/users/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.httpBody)
    }

    func testOpenIncidentsParsesFieldsWithGlobalPriority() async throws {
        let transport = try ventasTransport()
        let client = AsanaClient(token: "tok", transport: transport)
        let incidents = try await openIncidents(client, project: "ventas")

        // 4 abiertas: la completada se descarta.
        XCTAssertEqual(incidents.map(\.id), [
            "1211000000000001", "1211000000000002", "1211000000000003", "1211000000000004",
        ])

        // Campo global "Incidencia" -> urgente; campos de texto/enum y resumen de consola.
        let first = incidents[0]
        XCTAssertEqual(first.collectionID, "asana-tubuencamino/ventas")
        XCTAssertEqual(first.collectionName, "Ventas")
        XCTAssertEqual(first.name, "No carga el listado de presupuestos")
        XCTAssertEqual(first.priority, .urgente)
        XCTAssertEqual(first.reporter, "María López")
        XCTAssertEqual(first.module, "Presupuestos")
        XCTAssertEqual(first.consoleErrors, 3)
        XCTAssertNil(first.dueOn)
        XCTAssertNil(first.assigneeName)
        XCTAssertEqual(
            first.createdAt.timeIntervalSince1970,
            isoDate("2026-10-14T08:15:30Z").timeIntervalSince1970 + 0.123,
            accuracy: 0.001
        )
        XCTAssertEqual(
            first.permalinkURL,
            URL(string: "https://app.asana.com/1/1199999999999999/project/1216898612014391/task/1211000000000001")
        )

        // "Prioridad Alta" -> alta; display_value null -> nil; fecha sin fracciones (fallback).
        let second = incidents[1]
        XCTAssertEqual(second.priority, .alta)
        XCTAssertNil(second.reporter)
        XCTAssertNil(second.module)
        XCTAssertNil(second.consoleErrors)
        XCTAssertEqual(second.dueOn, "2026-10-20")
        XCTAssertEqual(second.assigneeName, "Joan Torres")
        XCTAssertEqual(second.assigneeID, "1200000000000001")
        XCTAssertNil(incidents[0].assigneeID)
        XCTAssertEqual(second.createdAt, isoDate("2026-10-13T17:02:11Z"))

        // Segunda página: "Baja" y prioridad vacía.
        XCTAssertEqual(incidents[2].priority, .baja)
        XCTAssertNil(incidents[2].consoleErrors)
        XCTAssertEqual(
            incidents[2].createdAt.timeIntervalSince1970,
            isoDate("2026-10-12T09:30:00Z").timeIntervalSince1970 + 0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(incidents[3].priority, .ninguna)
        XCTAssertEqual(incidents[3].consoleErrors, 0)
    }

    func testOpenIncidentsUsesLocalPriorityFieldInTBCIncidencias() async throws {
        let body = try fixture("tasks_general")
        let transport = MockTransport { _ in MockResponse(body: body) }
        let client = AsanaClient(token: "tok", transport: transport)
        let incidents = try await openIncidents(client, project: "general")

        XCTAssertEqual(incidents.map(\.id), ["1212000000000001", "1212000000000002"])
        // Trae el campo global en "Baja", pero TBC Incidencias usa su campo local ("Alta").
        XCTAssertEqual(incidents[0].priority, .alta)
        XCTAssertEqual(incidents[0].consoleErrors, 2)
        XCTAssertEqual(incidents[1].priority, .urgente)
        XCTAssertEqual(incidents[1].collectionID, "asana-tubuencamino/general")
        XCTAssertEqual(incidents[1].collectionName, "TBC")
        XCTAssertNil(incidents[1].consoleErrors)
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(queryValue(request, "section"), generalDetectadas)
    }

    func testOpenIncidentsWithoutOptionalFieldsIgnoresCustomFields() async throws {
        let transport = try ventasTransport()
        let client = AsanaClient(token: "tok", transport: transport)
        let collection = WatchedCollection(id: "src/ventas", name: "Ventas")
        let bare = AsanaProjectConfig(
            collection: collection,
            projectGid: "1216898612014391",
            projectName: "Ventas Incidencias",
            detectedSectionGid: "1219500158564901"
        )

        let incidents = try await client.openIncidents(in: bare, collection: collection)

        XCTAssertEqual(incidents.count, 4)
        XCTAssertEqual(incidents[0].collectionID, "src/ventas")
        XCTAssertTrue(incidents.allSatisfy { $0.priority == .ninguna })
        XCTAssertTrue(incidents.allSatisfy { $0.reporter == nil && $0.module == nil })
        // El resumen de consola no depende de la configuración.
        XCTAssertEqual(incidents[0].consoleErrors, 3)
    }

    func testOpenIncidentsPaginatesWithOffset() async throws {
        let transport = try ventasTransport()
        let client = AsanaClient(token: "tok", transport: transport)
        _ = try await openIncidents(client, project: "ventas")

        let requests = transport.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/1.0/tasks")
            XCTAssertEqual(queryValue(request, "section"), ventasDetectadas)
            XCTAssertEqual(queryValue(request, "completed_since"), "now")
            XCTAssertEqual(queryValue(request, "limit"), "100")
            XCTAssertEqual(queryValue(request, "opt_fields"), expectedOptFields)
        }
        XCTAssertNil(queryValue(requests[0], "offset"))
        XCTAssertEqual(queryValue(requests[1], "offset"), page2Offset)
    }

    func testOpenIncidentsStopsOnRepeatedOffsetAndDeduplicates() async throws {
        // El servidor devuelve siempre la misma página con el mismo next_page.
        let page1 = try fixture("tasks_ventas_page1")
        let transport = MockTransport { _ in MockResponse(body: page1) }
        let client = AsanaClient(token: "tok", transport: transport)
        let incidents = try await openIncidents(client, project: "ventas")

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(incidents.map(\.id), ["1211000000000001", "1211000000000002"])
    }

    func testOpenIncidentsStopsAtMaxPages() async throws {
        // Cada página apunta a otra distinta: el tope corta la paginación.
        let transport = MockTransport { request in
            let current = Int(queryValue(request, "offset") ?? "0") ?? 0
            return MockResponse(body: Data(#"{"data":[],"next_page":{"offset":"\#(current + 1)"}}"#.utf8))
        }
        let client = AsanaClient(token: "tok", transport: transport)
        let incidents = try await openIncidents(client, project: "ventas")

        XCTAssertTrue(incidents.isEmpty)
        XCTAssertEqual(transport.requests.count, AsanaClient.maxPages)
    }

    func testOffsetWithPlusIsPercentEncoded() async throws {
        let transport = MockTransport { request in
            if queryValue(request, "offset") == nil {
                return MockResponse(body: Data(#"{"data":[],"next_page":{"offset":"abc+def"}}"#.utf8))
            }
            return MockResponse(body: Data(#"{"data":[],"next_page":null}"#.utf8))
        }
        let client = AsanaClient(token: "tok", transport: transport)
        _ = try await openIncidents(client, project: "ventas")

        XCTAssertEqual(transport.requests.count, 2)
        let second = try XCTUnwrap(transport.requests.last)
        let url = try XCTUnwrap(second.url)
        let encodedQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        XCTAssertTrue(encodedQuery.contains("offset=abc%2Bdef"), encodedQuery)
        XCTAssertEqual(queryValue(second, "offset"), "abc+def")
    }

    // MARK: - Errores

    func testUnauthorizedMapsToUnauthorized() async throws {
        let transport = MockTransport { _ in
            MockResponse(status: 401, body: Data(#"{"errors":[{"message":"Not Authorized"}]}"#.utf8))
        }
        let client = AsanaClient(token: "malo", transport: transport)

        do {
            _ = try await client.me()
            XCTFail("Debería lanzar .unauthorized")
        } catch let error as SourceError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testRateLimitedCarriesRetryAfter() async throws {
        let transport = MockTransport { _ in
            MockResponse(status: 429, body: Data("{}".utf8), headers: ["Retry-After": "17"])
        }
        let client = AsanaClient(token: "tok", transport: transport)

        do {
            _ = try await openIncidents(client, project: "ventas")
            XCTFail("Debería lanzar .rateLimited")
        } catch let error as SourceError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 17))
        }
    }

    func testRateLimitedWithoutRetryAfter() async throws {
        let transport = MockTransport { _ in MockResponse(status: 429, body: Data("{}".utf8)) }
        let client = AsanaClient(token: "tok", transport: transport)

        do {
            _ = try await client.me()
            XCTFail("Debería lanzar .rateLimited")
        } catch let error as SourceError {
            XCTAssertEqual(error, .rateLimited(retryAfter: nil))
        }
    }

    func testOtherHTTPErrorCarriesAsanaMessage() async throws {
        let transport = MockTransport { _ in
            MockResponse(status: 500, body: Data(#"{"errors":[{"message":"Server Error"}]}"#.utf8))
        }
        let client = AsanaClient(token: "tok", transport: transport)

        do {
            _ = try await client.me()
            XCTFail("Debería lanzar .http")
        } catch let error as SourceError {
            XCTAssertEqual(error, .http(500, "Server Error"))
        }
    }

    func testInvalidJSONThrowsDecoding() async throws {
        let transport = MockTransport { _ in MockResponse(body: Data("no es json".utf8)) }
        let client = AsanaClient(token: "tok", transport: transport)

        do {
            _ = try await openIncidents(client, project: "ventas")
            XCTFail("Debería lanzar .decoding")
        } catch let error as SourceError {
            guard case .decoding = error else {
                return XCTFail("Error inesperado: \(error)")
            }
        }
    }

    func testTransportFailureMapsToNetwork() async throws {
        let transport = MockTransport { _ in throw TestSupportError.invalidResponse }
        let client = AsanaClient(token: "tok", transport: transport)

        do {
            _ = try await client.me()
            XCTFail("Debería lanzar .network")
        } catch let error as SourceError {
            guard case .network = error else {
                return XCTFail("Error inesperado: \(error)")
            }
        }
    }

    func testActionsPropagateErrors() async throws {
        let transport = MockTransport { _ in MockResponse(status: 401, body: Data("{}".utf8)) }
        let client = AsanaClient(token: "tok", transport: transport)

        do {
            try await client.assignToMe(sample, statusField: AsanaPresets.tbcStatus)
            XCTFail("Debería lanzar .unauthorized")
        } catch let error as SourceError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    // MARK: - Acciones

    func testAssignToMe() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let client = AsanaClient(token: "tok", transport: transport)

        try await client.assignToMe(sample, statusField: AsanaPresets.tbcStatus)

        XCTAssertEqual(transport.requests.count, 1)
        try assertAction(
            transport.requests.first,
            method: "PUT",
            url: taskURL,
            body: #"{"data":{"assignee":"me","custom_fields":{"1214163825159804":"1214163825159805"}}}"#
        )
    }

    func testAssignToMeWithoutStatusFieldOnlyAssigns() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let client = AsanaClient(token: "tok", transport: transport)

        try await client.assignToMe(sample, statusField: nil)

        try assertAction(transport.requests.first, method: "PUT", url: taskURL, body: #"{"data":{"assignee":"me"}}"#)
    }

    func testStartProgressAssignsWhenTaskHasNoAssignee() async throws {
        let transport = MockTransport { request in
            request.httpMethod == "GET"
                ? MockResponse(body: Data(#"{"data":{"gid":"1211000000000001","assignee":null}}"#.utf8))
                : MockResponse()
        }
        let client = AsanaClient(token: "tok", transport: transport)

        try await client.startProgress(sample, statusField: AsanaPresets.tbcStatus)

        XCTAssertEqual(transport.requests.count, 2)
        let lookup = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(lookup.httpMethod, "GET")
        XCTAssertEqual(lookup.url?.path, "/api/1.0/tasks/1211000000000001")
        XCTAssertEqual(queryValue(lookup, "opt_fields"), "assignee.gid")
        try assertAction(
            transport.requests.last,
            method: "PUT",
            url: taskURL,
            body: #"{"data":{"assignee":"me","custom_fields":{"1214163825159804":"1214163825159805"}}}"#
        )
    }

    func testStartProgressKeepsExistingAssignee() async throws {
        let transport = MockTransport { request in
            request.httpMethod == "GET"
                ? MockResponse(body: Data(#"{"data":{"gid":"1211000000000001","assignee":{"gid":"1200000000000002"}}}"#.utf8))
                : MockResponse()
        }
        let client = AsanaClient(token: "tok", transport: transport)

        try await client.startProgress(sample, statusField: AsanaPresets.tbcStatus)

        try assertAction(
            transport.requests.last,
            method: "PUT",
            url: taskURL,
            body: #"{"data":{"custom_fields":{"1214163825159804":"1214163825159805"}}}"#
        )
    }

    func testStartProgressDoesNotUpdateWhenLookupFails() async throws {
        let transport = MockTransport { _ in MockResponse(status: 404, body: Data(#"{"errors":[{"message":"Not found"}]}"#.utf8)) }
        let client = AsanaClient(token: "tok", transport: transport)

        do {
            try await client.startProgress(sample, statusField: AsanaPresets.tbcStatus)
            XCTFail("Debería lanzar .http")
        } catch let error as SourceError {
            guard case .http(404, _) = error else { return XCTFail("Error inesperado: \(error)") }
        }
        XCTAssertEqual(transport.requests.map(\.httpMethod), ["GET"])
    }

    func testMoveToSection() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let client = AsanaClient(token: "tok", transport: transport)

        let ventas = try XCTUnwrap(try presetProject("ventas").resolvedSectionGid)
        let general = try XCTUnwrap(try presetProject("general").resolvedSectionGid)

        try await client.move(sample, toSection: ventas)
        try await client.move(sample, toSection: general)

        let requests = transport.requests
        XCTAssertEqual(requests.count, 2)
        try assertAction(
            requests.first,
            method: "POST",
            url: "https://app.asana.com/api/1.0/sections/1219499888926675/addTask",
            body: #"{"data":{"task":"1211000000000001"}}"#
        )
        try assertAction(
            requests.last,
            method: "POST",
            url: "https://app.asana.com/api/1.0/sections/1214164017398879/addTask",
            body: #"{"data":{"task":"1211000000000001"}}"#
        )
    }

    func testSetDueDateWithDate() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let client = AsanaClient(token: "tok", transport: transport)

        try await client.setDueDate(sample, dueOn: "2026-10-20")

        XCTAssertEqual(transport.requests.count, 1)
        try assertAction(
            transport.requests.first,
            method: "PUT",
            url: taskURL,
            body: #"{"data":{"due_on":"2026-10-20"}}"#
        )
    }

    func testSetDueDateWithNull() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let client = AsanaClient(token: "tok", transport: transport)

        try await client.setDueDate(sample, dueOn: nil)

        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        try assertAction(request, method: "PUT", url: taskURL, body: #"{"data":{"due_on":null}}"#)
        // Es un null JSON de verdad, no la cadena "null" ni la clave ausente.
        let data = try XCTUnwrap(try jsonObject(request)["data"] as? [String: Any])
        XCTAssertTrue(data["due_on"] is NSNull)
    }

    func testSetPriorityGlobalField() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let client = AsanaClient(token: "tok", transport: transport)

        let field = try XCTUnwrap(try presetProject("ventas").priorityField)

        try await client.setPriority(sample, priority: .alta, field: field)

        XCTAssertEqual(transport.requests.count, 1)
        try assertAction(
            transport.requests.first,
            method: "PUT",
            url: taskURL,
            body: #"{"data":{"custom_fields":{"1219502866938804":"1219502866938808"}}}"#
        )
    }

    func testSetPriorityLocalFieldInTBCIncidencias() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let client = AsanaClient(token: "tok", transport: transport)

        let field = try XCTUnwrap(try presetProject("general").priorityField)

        try await client.setPriority(sample, priority: .urgente, field: field)

        XCTAssertEqual(transport.requests.count, 1)
        try assertAction(
            transport.requests.first,
            method: "PUT",
            url: taskURL,
            body: #"{"data":{"custom_fields":{"1214164017398881":"1214164017398884"}}}"#
        )
    }

    func testSetPriorityNingunaClearsField() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let client = AsanaClient(token: "tok", transport: transport)

        let field = try XCTUnwrap(try presetProject("ventas").priorityField)

        try await client.setPriority(sample, priority: .ninguna, field: field)

        XCTAssertEqual(transport.requests.count, 1)
        try assertAction(
            transport.requests.first,
            method: "PUT",
            url: taskURL,
            body: #"{"data":{"custom_fields":{"1219502866938804":null}}}"#
        )
    }

    func testBaseURLWithTrailingSlash() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let baseURL = try XCTUnwrap(URL(string: "https://example.test/api/1.0/"))
        let client = AsanaClient(token: "tok", transport: transport, baseURL: baseURL)

        try await client.setDueDate(sample, dueOn: nil)

        XCTAssertEqual(
            transport.requests.first?.url?.absoluteString,
            "https://example.test/api/1.0/tasks/1211000000000001"
        )
    }
}
