import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NotchwatchCore

final class AsanaSourceTests: XCTestCase {
    private let taskURL = "https://app.asana.com/api/1.0/tasks/1211000000000001"

    private func incident(in key: String) -> Incident {
        sampleIncident("1211000000000001", createdAt: isoDate("2026-10-14T08:00:00Z"), collectionKey: key)
    }

    // MARK: - Identidad y colecciones

    func testExposesConfigAsCollections() throws {
        let source = presetSource(enabling: ["ventas", "general"], transport: MockTransport { _ in MockResponse() })

        XCTAssertEqual(source.id, "asana-tubuencamino")
        XCTAssertEqual(source.kind, .asana)
        XCTAssertEqual(source.displayName, "Tubuencamino")
        XCTAssertEqual(source.collections.count, 7)
        XCTAssertEqual(source.collections.filter(\.enabled).map(\.id), [tbcCollectionID("ventas"), tbcCollectionID("general")])
    }

    func testIdentityUsesMe() async throws {
        let body = try fixture("me")
        let transport = MockTransport { _ in MockResponse(body: body) }
        let source = presetSource(enabling: ["ventas"], token: "tok-123", transport: transport)

        let identity = try await source.identity()

        XCTAssertEqual(identity, SourceIdentity(userID: "1200000000000001", name: "Joan Torres"))
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
    }

    func testOpenIncidentsUsesTheProjectOfTheCollection() async throws {
        let general = try fixture("tasks_general")
        let transport = MockTransport { _ in MockResponse(body: general) }
        let source = presetSource(enabling: ["general"], transport: transport)
        let collection = try presetProject("general").collection

        let incidents = try await source.openIncidents(in: collection)

        XCTAssertEqual(incidents.map(\.id), ["1212000000000001", "1212000000000002"])
        XCTAssertEqual(incidents[0].collectionID, tbcCollectionID("general"))
        XCTAssertEqual(incidents[0].collectionName, "TBC")
        XCTAssertEqual(incidents[0].priority, .alta)
        XCTAssertEqual(queryValue(try XCTUnwrap(transport.requests.first), "section"), "1214164017398877")
    }

    func testOpenIncidentsOfUnknownCollectionIsInvalidConfiguration() async throws {
        let source = presetSource(enabling: ["ventas"], transport: MockTransport { _ in MockResponse() })

        do {
            _ = try await source.openIncidents(in: WatchedCollection(id: "otra/x", name: "X"))
            XCTFail("Debería lanzar .invalidConfiguration")
        } catch let error as SourceError {
            guard case .invalidConfiguration = error else { return XCTFail("Error inesperado: \(error)") }
        }
    }

    // MARK: - Capacidades

    func testPresetHasAllCapabilities() {
        let source = presetSource(enabling: ["ventas", "general"], transport: MockTransport { _ in MockResponse() })
        XCTAssertEqual(source.capabilities, [.assignToMe, .resolve, .dueDate, .priority])
    }

    func testCapabilitiesDropResolveAndPriorityWhenAnEnabledProjectLacksThem() {
        var config = presetConfig(enabling: ["ventas", "finanzas"])
        config.projects[1].resolvedSectionGid = nil
        config.projects[1].priorityField = nil
        let source = AsanaSource(config: config, token: "tok", transport: MockTransport { _ in MockResponse() })

        XCTAssertEqual(source.capabilities, [.assignToMe, .dueDate])

        // Si ese proyecto está desactivado, no cuenta.
        config.projects[1].collection.enabled = false
        let narrowed = AsanaSource(config: config, token: "tok", transport: MockTransport { _ in MockResponse() })
        XCTAssertEqual(narrowed.capabilities, [.assignToMe, .resolve, .dueDate, .priority])
    }

    // MARK: - Acciones

    func testAssignToMeSetsStatusOfTheProject() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let source = presetSource(enabling: ["ventas"], transport: transport)

        try await source.perform(.assignToMe, on: incident(in: "ventas"))

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.absoluteString, taskURL)
        XCTAssertEqual(
            bodyString(request),
            #"{"data":{"assignee":"me","custom_fields":{"1214163825159804":"1214163825159805"}}}"#
        )
    }

    func testResolveMovesToTheResolvedSectionOfTheProject() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let source = presetSource(enabling: ["ventas", "general"], transport: transport)

        try await source.perform(.resolve, on: incident(in: "ventas"))
        try await source.perform(.resolve, on: incident(in: "general"))

        let requests = transport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "POST"])
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://app.asana.com/api/1.0/sections/1219499888926675/addTask",
            "https://app.asana.com/api/1.0/sections/1214164017398879/addTask",
        ])
        XCTAssertEqual(bodyString(requests[0]), #"{"data":{"task":"1211000000000001"}}"#)
    }

    func testResolveWithoutResolvedSectionIsInvalidConfigurationAndSendsNothing() async throws {
        let transport = MockTransport { _ in MockResponse() }
        var config = presetConfig(enabling: ["ventas"])
        config.projects[0].resolvedSectionGid = nil
        let source = AsanaSource(config: config, token: "tok", transport: transport)

        do {
            try await source.perform(.resolve, on: incident(in: "ventas"))
            XCTFail("Debería lanzar .invalidConfiguration")
        } catch let error as SourceError {
            guard case .invalidConfiguration = error else { return XCTFail("Error inesperado: \(error)") }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSetDueDate() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let source = presetSource(enabling: ["ventas"], transport: transport)

        try await source.perform(.setDueDate("2026-10-20"), on: incident(in: "ventas"))
        try await source.perform(.setDueDate(nil), on: incident(in: "ventas"))

        let requests = transport.requests
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [taskURL, taskURL])
        XCTAssertEqual(bodyString(requests[0]), #"{"data":{"due_on":"2026-10-20"}}"#)
        XCTAssertEqual(bodyString(requests[1]), #"{"data":{"due_on":null}}"#)
    }

    func testSetPriorityUsesTheFieldOfTheProject() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let source = presetSource(enabling: ["ventas", "general"], transport: transport)

        try await source.perform(.setPriority(.alta), on: incident(in: "ventas"))
        try await source.perform(.setPriority(.urgente), on: incident(in: "general"))

        let requests = transport.requests
        XCTAssertEqual(bodyString(requests[0]), #"{"data":{"custom_fields":{"1219502866938804":"1219502866938808"}}}"#)
        XCTAssertEqual(bodyString(requests[1]), #"{"data":{"custom_fields":{"1214164017398881":"1214164017398884"}}}"#)
    }

    func testSetPriorityWithoutFieldIsInvalidConfiguration() async throws {
        let transport = MockTransport { _ in MockResponse() }
        var config = presetConfig(enabling: ["ventas"])
        config.projects[0].priorityField = nil
        let source = AsanaSource(config: config, token: "tok", transport: transport)

        do {
            try await source.perform(.setPriority(.alta), on: incident(in: "ventas"))
            XCTFail("Debería lanzar .invalidConfiguration")
        } catch let error as SourceError {
            guard case .invalidConfiguration = error else { return XCTFail("Error inesperado: \(error)") }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testPerformOnIncidentOfUnknownCollectionIsInvalidConfiguration() async throws {
        let transport = MockTransport { _ in MockResponse() }
        let source = presetSource(enabling: ["ventas"], transport: transport)
        var foreign = incident(in: "ventas")
        foreign.collectionID = "github/x"

        do {
            try await source.perform(.assignToMe, on: foreign)
            XCTFail("Debería lanzar .invalidConfiguration")
        } catch let error as SourceError {
            guard case .invalidConfiguration = error else { return XCTFail("Error inesperado: \(error)") }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testPerformPropagatesTransportErrors() async throws {
        let transport = MockTransport { _ in MockResponse(status: 429, body: Data("{}".utf8), headers: ["Retry-After": "5"]) }
        let source = presetSource(enabling: ["ventas"], transport: transport)

        do {
            try await source.perform(.assignToMe, on: incident(in: "ventas"))
            XCTFail("Debería lanzar .rateLimited")
        } catch let error as SourceError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 5))
        }
    }
}
