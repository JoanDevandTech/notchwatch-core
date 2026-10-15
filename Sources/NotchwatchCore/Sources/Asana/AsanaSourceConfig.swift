import Foundation

/// Cuenta de Asana configurada: un workspace y los proyectos vigilados en él.
public struct AsanaSourceConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var workspaceGid: String
    public var workspaceName: String
    public var projects: [AsanaProjectConfig]

    public init(
        id: String,
        displayName: String,
        workspaceGid: String,
        workspaceName: String,
        projects: [AsanaProjectConfig]
    ) {
        self.id = id
        self.displayName = displayName
        self.workspaceGid = workspaceGid
        self.workspaceName = workspaceName
        self.projects = projects
    }
}

/// Proyecto de Asana vigilado y cómo se leen sus incidencias.
public struct AsanaProjectConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: String { collection.id }
    public var collection: WatchedCollection
    public var projectGid: String
    public var projectName: String
    /// Sección cuyas tareas abiertas son incidencias pendientes.
    public var detectedSectionGid: String
    /// Sección a la que se mueve una incidencia al «resolverla». Sin ella, la fuente no ofrece resolver.
    public var resolvedSectionGid: String?
    public var priorityField: PriorityField?
    /// Campo que se pone «en curso» al asignarse la incidencia.
    public var statusField: StatusField?
    /// Campos de texto opcionales que enriquecen la incidencia.
    public var reporterFieldGid: String?
    public var moduleFieldGid: String?

    public init(
        collection: WatchedCollection,
        projectGid: String,
        projectName: String,
        detectedSectionGid: String,
        resolvedSectionGid: String? = nil,
        priorityField: PriorityField? = nil,
        statusField: StatusField? = nil,
        reporterFieldGid: String? = nil,
        moduleFieldGid: String? = nil
    ) {
        self.collection = collection
        self.projectGid = projectGid
        self.projectName = projectName
        self.detectedSectionGid = detectedSectionGid
        self.resolvedSectionGid = resolvedSectionGid
        self.priorityField = priorityField
        self.statusField = statusField
        self.reporterFieldGid = reporterFieldGid
        self.moduleFieldGid = moduleFieldGid
    }
}

/// Campo enum de prioridad y sus opciones.
public struct PriorityField: Codable, Hashable, Sendable {
    public var fieldGid: String
    /// Prioridad → GID de la opción en Asana.
    public var options: [IncidentPriority: String]

    public init(fieldGid: String, options: [IncidentPriority: String]) {
        self.fieldGid = fieldGid
        self.options = options
    }

    /// Prioridad de la opción seleccionada; `.ninguna` si no hay o no se reconoce.
    public func priority(forOptionGid gid: String?) -> IncidentPriority {
        guard let gid, !gid.isEmpty else { return .ninguna }
        for priority in IncidentPriority.allCases where options[priority] == gid {
            return priority
        }
        return .ninguna
    }
}

/// Campo enum de estado con las opciones que significan «en curso» y «solucionada».
/// `solvedOptionGid` es opcional para leer perfiles guardados antes de existir; si falta,
/// el cliente la busca en Asana al resolver.
public struct StatusField: Codable, Hashable, Sendable {
    public var fieldGid: String
    public var inProgressOptionGid: String
    public var solvedOptionGid: String?

    public init(fieldGid: String, inProgressOptionGid: String, solvedOptionGid: String? = nil) {
        self.fieldGid = fieldGid
        self.inProgressOptionGid = inProgressOptionGid
        self.solvedOptionGid = solvedOptionGid
    }
}

// MARK: - Descubrimiento

/// Lo que la app enseña al elegir proyectos: workspaces, proyectos, secciones y campos.
public struct AsanaWorkspace: Codable, Equatable, Sendable, Identifiable {
    public var id: String { gid }
    public var gid: String
    public var name: String

    public init(gid: String, name: String) {
        self.gid = gid
        self.name = name
    }
}

public struct AsanaProject: Codable, Equatable, Sendable, Identifiable {
    public var id: String { gid }
    public var gid: String
    public var name: String
    public var archived: Bool

    public init(gid: String, name: String, archived: Bool = false) {
        self.gid = gid
        self.name = name
        self.archived = archived
    }
}

public struct AsanaSection: Codable, Equatable, Sendable, Identifiable {
    public var id: String { gid }
    public var gid: String
    public var name: String

    public init(gid: String, name: String) {
        self.gid = gid
        self.name = name
    }
}

public struct AsanaCustomField: Codable, Equatable, Sendable, Identifiable {
    public struct Option: Codable, Equatable, Sendable, Identifiable {
        public var id: String { gid }
        public var gid: String
        public var name: String

        public init(gid: String, name: String) {
            self.gid = gid
            self.name = name
        }
    }

    public var id: String { gid }
    public var gid: String
    public var name: String
    /// «enum», «text», «number»…
    public var type: String
    public var options: [Option]

    public init(gid: String, name: String, type: String, options: [Option] = []) {
        self.gid = gid
        self.name = name
        self.type = type
        self.options = options
    }
}

/// Todo lo que hace falta para proponer la configuración de un proyecto.
public struct AsanaProjectLayout: Equatable, Sendable {
    public var project: AsanaProject
    public var sections: [AsanaSection]
    public var fields: [AsanaCustomField]

    public init(project: AsanaProject, sections: [AsanaSection], fields: [AsanaCustomField]) {
        self.project = project
        self.sections = sections
        self.fields = fields
    }
}
