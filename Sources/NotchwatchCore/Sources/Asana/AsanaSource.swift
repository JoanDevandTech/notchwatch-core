import Foundation

/// Fuente Asana: expone los proyectos de una cuenta como colecciones y ejecuta las acciones
/// sobre `AsanaClient`.
public final class AsanaSource: IncidentSource {
    public let config: AsanaSourceConfig
    public let client: AsanaClient

    public init(config: AsanaSourceConfig, token: String, transport: HTTPTransport = URLSessionTransport()) {
        self.config = config
        self.client = AsanaClient(token: token, transport: transport)
    }

    public var id: String { config.id }
    public var kind: SourceKind { .asana }
    public var displayName: String { config.displayName }
    public var collections: [WatchedCollection] { config.projects.map(\.collection) }

    /// Resolver, prioridad y «en curso» solo se anuncian si TODOS los proyectos activos lo permiten; aun así,
    /// `perform` lo intenta y falla con `invalidConfiguration` en el proyecto que no puede.
    public var capabilities: SourceCapabilities {
        var capabilities: SourceCapabilities = [.assignToMe, .dueDate]
        let enabled = config.projects.filter { $0.collection.enabled }
        if enabled.allSatisfy({ $0.resolvedSectionGid != nil }) {
            capabilities.insert(.resolve)
        }
        if enabled.allSatisfy({ $0.priorityField != nil }) {
            capabilities.insert(.priority)
        }
        if enabled.allSatisfy({ $0.statusField != nil }) {
            capabilities.insert(.startProgress)
        }
        return capabilities
    }

    public func identity() async throws -> SourceIdentity {
        try await client.me()
    }

    public func openIncidents(in collection: WatchedCollection) async throws -> [Incident] {
        let project = try project(forCollectionID: collection.id)
        return try await client.openIncidents(in: project, collection: collection)
    }

    public func perform(_ action: IncidentAction, on incident: Incident) async throws {
        let project = try project(forCollectionID: incident.collectionID)
        switch action {
        case .assignToMe:
            try await client.assignToMe(incident, statusField: project.statusField)
        case .startProgress:
            guard let field = project.statusField else {
                throw SourceError.invalidConfiguration("El proyecto «\(project.projectName)» no tiene campo de estado")
            }
            try await client.startProgress(incident, statusField: field)
        case .resolve:
            guard let section = project.resolvedSectionGid else {
                throw SourceError.invalidConfiguration("El proyecto «\(project.projectName)» no tiene sección de resueltas")
            }
            try await client.resolve(incident, toSection: section, statusField: project.statusField)
        case .setDueDate(let dueOn):
            try await client.setDueDate(incident, dueOn: dueOn)
        case .setPriority(let priority):
            guard let field = project.priorityField else {
                throw SourceError.invalidConfiguration("El proyecto «\(project.projectName)» no tiene campo de prioridad")
            }
            try await client.setPriority(incident, priority: priority, field: field)
        }
    }

    /// Proyecto configurado para una colección; la fuente no sabe nada de colecciones ajenas.
    public func project(forCollectionID collectionID: String) throws -> AsanaProjectConfig {
        guard let project = config.projects.first(where: { $0.collection.id == collectionID }) else {
            throw SourceError.invalidConfiguration("Colección desconocida: \(collectionID)")
        }
        return project
    }
}
