import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cliente mínimo de la API REST de Asana: lee y gestiona incidencias y descubre la estructura
/// de un workspace para el asistente de alta.
public final class AsanaClient: Sendable {
    private let token: String
    private let transport: HTTPTransport
    private let baseURL: URL

    /// Campos pedidos al listar tareas.
    static let taskOptFields = "name,created_at,due_on,notes,permalink_url,completed,assignee.gid,assignee.name,custom_fields.gid,custom_fields.display_value,custom_fields.enum_value.gid"
    /// Campos pedidos al listar los ajustes de campos personalizados de un proyecto.
    static let customFieldOptFields = "custom_field.gid,custom_field.name,custom_field.type,custom_field.enum_options.gid,custom_field.enum_options.name,custom_field.enum_options.enabled"
    /// Tamaño de página (máximo admitido por Asana).
    static let pageLimit = 100
    /// Tope de páginas por listado: red de seguridad ante un `next_page` que nunca se agota.
    static let maxPages = 50

    public init(
        token: String,
        transport: HTTPTransport = URLSessionTransport(),
        baseURL: URL = URL(string: "https://app.asana.com/api/1.0")!
    ) {
        self.token = token
        self.transport = transport
        self.baseURL = baseURL
    }

    // MARK: - Lectura

    /// Usuario dueño del token (sirve para «Probar conexión»).
    public func me() async throws -> SourceIdentity {
        let request = try makeRequest(
            method: "GET",
            path: "users/me",
            query: [URLQueryItem(name: "opt_fields", value: "gid,name")]
        )
        let data = try await perform(request)
        let envelope = try decode(DataEnvelope<NamedDTO>.self, from: data)
        return SourceIdentity(userID: envelope.data.gid, name: envelope.data.name ?? "")
    }

    /// Tareas abiertas de la sección «detectadas» del proyecto, como incidencias de `collection`.
    public func openIncidents(in project: AsanaProjectConfig, collection: WatchedCollection) async throws -> [Incident] {
        let tasks: [TaskDTO] = try await fetchAllPages(path: "tasks", query: [
            URLQueryItem(name: "section", value: project.detectedSectionGid),
            URLQueryItem(name: "completed_since", value: "now"),
            URLQueryItem(name: "opt_fields", value: AsanaClient.taskOptFields),
        ])
        // `completed_since=now` ya filtra; se descartan también las completadas por si acaso.
        return tasks
            .filter { $0.completed != true }
            .map { makeIncident(from: $0, project: project, collection: collection) }
    }

    // MARK: - Acciones

    /// Asigna la tarea al usuario del token y, si se indica, pone el campo de estado en «en curso».
    public func assignToMe(_ incident: Incident, statusField: StatusField?) async throws {
        var fields: [String: Any] = ["assignee": "me"]
        if let statusField {
            fields["custom_fields"] = [statusField.fieldGid: statusField.inProgressOptionGid]
        }
        try await updateTask(incident, fields: fields)
    }

    /// Pone el campo de estado en «en curso» y asigna la tarea al usuario del token solo si,
    /// según Asana en ese momento, no tiene responsable.
    public func startProgress(_ incident: Incident, statusField: StatusField) async throws {
        let request = try makeRequest(
            method: "GET",
            path: "tasks/\(incident.id)",
            query: [URLQueryItem(name: "opt_fields", value: "assignee.gid")]
        )
        let data = try await perform(request)
        let task = try decode(DataEnvelope<TaskAssigneeDTO>.self, from: data).data
        var fields: [String: Any] = ["custom_fields": [statusField.fieldGid: statusField.inProgressOptionGid]]
        if Text.nonEmpty(task.assignee?.gid) == nil {
            fields["assignee"] = "me"
        }
        try await updateTask(incident, fields: fields)
    }

    /// Mueve la tarea a la sección indicada.
    public func move(_ incident: Incident, toSection sectionGid: String) async throws {
        let request = try makeRequest(
            method: "POST",
            path: "sections/\(sectionGid)/addTask",
            body: ["data": ["task": incident.id]]
        )
        _ = try await perform(request)
    }

    /// Mueve la tarea a la sección de resueltas y, si el proyecto tiene campo de estado, lo pone en
    /// «solucionada». El estado va después del movimiento para que las reglas de Asana que reaccionan
    /// a él (completar, pasar a Histórico) actúen sobre la tarea ya movida.
    public func resolve(_ incident: Incident, toSection sectionGid: String, statusField: StatusField?) async throws {
        try await move(incident, toSection: sectionGid)
        guard let statusField else { return }
        let solved: String?
        if let known = statusField.solvedOptionGid {
            solved = known
        } else {
            solved = try await solvedOption(ofField: statusField.fieldGid)
        }
        guard let solved else { return }
        try await updateTask(incident, fields: ["custom_fields": [statusField.fieldGid: solved]])
    }

    /// Opción «solucionada» de un campo enum, buscada por nombre entre las habilitadas.
    func solvedOption(ofField fieldGid: String) async throws -> String? {
        let request = try makeRequest(
            method: "GET",
            path: "custom_fields/\(fieldGid)",
            query: [URLQueryItem(name: "opt_fields", value: "enum_options.gid,enum_options.name,enum_options.enabled")]
        )
        let data = try await perform(request)
        let field = try decode(DataEnvelope<CustomFieldDefinitionDTO>.self, from: data).data
        return field.enumOptions?
            .first { $0.enabled != false && AsanaConfigurator.contains($0.name ?? "", anyOf: AsanaConfigurator.solvedHints) }?
            .gid
    }

    /// Fija (o quita, con `nil`) la fecha de vencimiento «YYYY-MM-DD».
    public func setDueDate(_ incident: Incident, dueOn: String?) async throws {
        try await updateTask(incident, fields: ["due_on": dueOn ?? NSNull()])
    }

    /// Cambia la prioridad usando el campo de prioridad del proyecto (`.ninguna` lo vacía).
    public func setPriority(_ incident: Incident, priority: IncidentPriority, field: PriorityField) async throws {
        let value: Any = field.options[priority] ?? NSNull()
        try await updateTask(incident, fields: ["custom_fields": [field.fieldGid: value]])
    }

    private func updateTask(_ incident: Incident, fields: [String: Any]) async throws {
        let request = try makeRequest(method: "PUT", path: "tasks/\(incident.id)", body: ["data": fields])
        _ = try await perform(request)
    }

    // MARK: - Descubrimiento

    public func workspaces() async throws -> [AsanaWorkspace] {
        let request = try makeRequest(method: "GET", path: "workspaces")
        let data = try await perform(request)
        let envelope = try decode(DataEnvelope<[NamedDTO]>.self, from: data)
        return envelope.data.map { AsanaWorkspace(gid: $0.gid, name: $0.name ?? "") }
    }

    /// Proyectos no archivados del workspace, paginados.
    public func projects(inWorkspace gid: String) async throws -> [AsanaProject] {
        let projects: [ProjectDTO] = try await fetchAllPages(path: "projects", query: [
            URLQueryItem(name: "workspace", value: gid),
            URLQueryItem(name: "archived", value: "false"),
            URLQueryItem(name: "opt_fields", value: "name,archived"),
        ])
        return projects.map { AsanaProject(gid: $0.gid, name: $0.name ?? "", archived: $0.archived ?? false) }
    }

    public func sections(ofProject gid: String) async throws -> [AsanaSection] {
        let request = try makeRequest(method: "GET", path: "projects/\(gid)/sections")
        let data = try await perform(request)
        let envelope = try decode(DataEnvelope<[NamedDTO]>.self, from: data)
        return envelope.data.map { AsanaSection(gid: $0.gid, name: $0.name ?? "") }
    }

    /// Campos personalizados del proyecto (vía `custom_field_settings`); solo opciones habilitadas.
    public func customFields(ofProject gid: String) async throws -> [AsanaCustomField] {
        let request = try makeRequest(
            method: "GET",
            path: "projects/\(gid)/custom_field_settings",
            query: [URLQueryItem(name: "opt_fields", value: AsanaClient.customFieldOptFields)]
        )
        let data = try await perform(request)
        let envelope = try decode(DataEnvelope<[CustomFieldSettingDTO]>.self, from: data)
        return envelope.data.compactMap { setting in
            guard let field = setting.customField else { return nil }
            let options = (field.enumOptions ?? [])
                .filter { $0.enabled != false }
                .map { AsanaCustomField.Option(gid: $0.gid, name: $0.name ?? "") }
            return AsanaCustomField(gid: field.gid, name: field.name ?? "", type: field.type ?? "", options: options)
        }
    }

    /// Secciones y campos del proyecto, pedidos en paralelo.
    public func layout(of project: AsanaProject) async throws -> AsanaProjectLayout {
        async let sections = sections(ofProject: project.gid)
        async let fields = customFields(ofProject: project.gid)
        return AsanaProjectLayout(project: project, sections: try await sections, fields: try await fields)
    }

    // MARK: - Mapeo

    func makeIncident(from task: TaskDTO, project: AsanaProjectConfig, collection: WatchedCollection) -> Incident {
        let fields = task.customFields ?? []
        let priority: IncidentPriority
        if let priorityField = project.priorityField {
            let option = fields.first(where: { $0.gid == priorityField.fieldGid })?.enumValue?.gid
            priority = priorityField.priority(forOptionGid: option)
        } else {
            priority = .ninguna
        }
        let reporter = project.reporterFieldGid.flatMap { gid in fields.first(where: { $0.gid == gid })?.displayValue }
        let module = project.moduleFieldGid.flatMap { gid in fields.first(where: { $0.gid == gid })?.displayValue }

        return Incident(
            id: task.gid,
            collectionID: collection.id,
            collectionName: collection.name,
            name: task.name ?? "(sin título)",
            priority: priority,
            reporter: Text.nonEmpty(reporter),
            module: Text.nonEmpty(module),
            consoleErrors: ConsoleSummaryParser.errorCount(fromNotes: task.notes),
            // Si created_at no viene o no se entiende, se trata como antigua.
            createdAt: AsanaClient.parseDate(task.createdAt) ?? Date(timeIntervalSince1970: 0),
            dueOn: Text.nonEmpty(task.dueOn),
            assigneeID: Text.nonEmpty(task.assignee?.gid),
            assigneeName: Text.nonEmpty(task.assignee?.name),
            permalinkURL: task.permalinkURL.flatMap { URL(string: $0) }
        )
    }

    /// Parsea fechas ISO8601 con o sin fracciones de segundo.
    static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        // ISO8601DateFormatter no es Sendable: se crea en cada llamada.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - Paginación

    /// Recorre un listado paginado por `offset` hasta agotarlo, descartando duplicados por GID.
    /// Corta ante un offset repetido o al llegar a `maxPages`.
    private func fetchAllPages<Item: Decodable & GIDIdentified>(path: String, query: [URLQueryItem]) async throws -> [Item] {
        var items: [Item] = []
        var gids = Set<String>()
        var offset: String?
        var usedOffsets = Set<String>()
        var pages = 0

        repeat {
            var pageQuery = query + [URLQueryItem(name: "limit", value: String(AsanaClient.pageLimit))]
            if let offset {
                pageQuery.append(URLQueryItem(name: "offset", value: offset))
            }
            let request = try makeRequest(method: "GET", path: path, query: pageQuery)
            let data = try await perform(request)
            let page = try decode(PageDTO<Item>.self, from: data)
            pages += 1

            for item in page.data where !gids.contains(item.gid) {
                gids.insert(item.gid)
                items.append(item)
            }

            offset = page.nextPage?.offset
            if let next = offset {
                if usedOffsets.contains(next) || pages >= AsanaClient.maxPages { break }
                usedOffsets.insert(next)
            }
        } while offset != nil

        return items
    }

    // MARK: - HTTP

    /// Construye la petición con cabeceras de autenticación y cuerpo JSON opcional.
    func makeRequest(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SourceError.invalidConfiguration("URL base inválida: \(baseURL)")
        }
        var basePath = components.path
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        components.path = basePath + "/" + path
        if !query.isEmpty {
            components.queryItems = query
            // URLComponents deja "+" sin codificar y muchos servidores lo leen como espacio.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else {
            throw SourceError.invalidConfiguration("URL inválida: \(components)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            } catch {
                throw SourceError.decoding("No se pudo codificar el cuerpo: \(error)")
            }
        }
        return request
    }

    /// Envía la petición y traduce los códigos de estado a `SourceError`.
    func perform(_ request: URLRequest) async throws -> Data {
        let result: (Data, HTTPURLResponse)
        do {
            result = try await transport.send(request)
        } catch let error as SourceError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SourceError.network(error.localizedDescription)
        }

        let (data, response) = result
        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw SourceError.unauthorized
        case 429:
            let header = response.value(forHTTPHeaderField: "Retry-After")
            let retryAfter = header.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            throw SourceError.rateLimited(retryAfter: retryAfter)
        default:
            throw SourceError.http(response.statusCode, AsanaClient.errorMessage(from: data))
        }
    }

    /// Decodifica envolviendo los errores en `SourceError.decoding`.
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SourceError.decoding(String(describing: error))
        }
    }

    /// Extrae el mensaje de error de Asana ({"errors":[{"message":…}]}) o el cuerpo en texto.
    static func errorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelopeDTO.self, from: data) {
            let messages = envelope.errors.compactMap { $0.message }
            if !messages.isEmpty {
                return messages.joined(separator: "; ")
            }
        }
        let text = String(decoding: data, as: UTF8.self)
        return String(text.prefix(300))
    }
}

// MARK: - DTOs de Asana

/// Elemento con GID, para deduplicar al paginar.
protocol GIDIdentified {
    var gid: String { get }
}

/// Envoltorio genérico {"data": …}.
struct DataEnvelope<T: Decodable>: Decodable {
    let data: T
}

/// Página de un listado con `next_page` (null en la última).
struct PageDTO<Item: Decodable>: Decodable {
    let data: [Item]
    let nextPage: NextPageDTO?

    enum CodingKeys: String, CodingKey {
        case data
        case nextPage = "next_page"
    }
}

struct NextPageDTO: Decodable {
    let offset: String?
}

/// Usuario, workspace o sección: solo GID y nombre.
struct NamedDTO: Decodable, GIDIdentified {
    let gid: String
    let name: String?
}

struct ProjectDTO: Decodable, GIDIdentified {
    let gid: String
    let name: String?
    let archived: Bool?
}

struct CustomFieldSettingDTO: Decodable {
    let customField: CustomFieldDefinitionDTO?

    enum CodingKeys: String, CodingKey {
        case customField = "custom_field"
    }
}

struct CustomFieldDefinitionDTO: Decodable {
    let gid: String
    let name: String?
    let type: String?
    let enumOptions: [EnumOptionDTO]?

    enum CodingKeys: String, CodingKey {
        case gid, name, type
        case enumOptions = "enum_options"
    }
}

struct EnumOptionDTO: Decodable {
    let gid: String
    let name: String?
    let enabled: Bool?
}

struct TaskDTO: Decodable, GIDIdentified {
    let gid: String
    let name: String?
    let createdAt: String?
    let dueOn: String?
    let notes: String?
    let permalinkURL: String?
    let completed: Bool?
    let assignee: AssigneeDTO?
    let customFields: [CustomFieldDTO]?

    enum CodingKeys: String, CodingKey {
        case gid, name, notes, completed, assignee
        case createdAt = "created_at"
        case dueOn = "due_on"
        case permalinkURL = "permalink_url"
        case customFields = "custom_fields"
    }
}

struct TaskAssigneeDTO: Decodable {
    let assignee: AssigneeDTO?
}

struct AssigneeDTO: Decodable {
    let gid: String?
    let name: String?
}

struct CustomFieldDTO: Decodable {
    let gid: String
    let displayValue: String?
    let enumValue: EnumValueDTO?

    enum CodingKeys: String, CodingKey {
        case gid
        case displayValue = "display_value"
        case enumValue = "enum_value"
    }
}

struct EnumValueDTO: Decodable {
    let gid: String?
}

struct ErrorEnvelopeDTO: Decodable {
    struct Item: Decodable {
        let message: String?
    }

    let errors: [Item]
}
