import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cliente mínimo de la API REST de Asana para leer y gestionar incidencias.
public final class AsanaClient: Sendable {
    private let token: String
    private let transport: HTTPTransport
    private let baseURL: URL

    /// Campos pedidos al listar tareas.
    static let optFields = "name,created_at,due_on,notes,permalink_url,completed,assignee.name,custom_fields.gid,custom_fields.display_value,custom_fields.enum_value.gid"
    /// Campo personalizado "Reportado por".
    static let reporterFieldGid = "1216067243827070"
    /// Campo personalizado "Módulo".
    static let moduleFieldGid = "1216067230748421"
    /// Tamaño de página (máximo admitido por Asana).
    static let pageLimit = 100
    /// Tope de páginas por sección: red de seguridad ante un `next_page` que nunca se agota.
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

    /// Usuario dueño del token (sirve para "Probar conexión").
    public func me() async throws -> (gid: String, name: String) {
        let request = try makeRequest(
            method: "GET",
            path: "users/me",
            query: [URLQueryItem(name: "opt_fields", value: "gid,name")]
        )
        let data = try await perform(request)
        let envelope = try decode(DataEnvelope<UserDTO>.self, from: data)
        return (gid: envelope.data.gid, name: envelope.data.name ?? "")
    }

    /// Tareas abiertas de la sección "detectadas" de un proyecto (pagina con offset hasta agotar).
    public func openIncidents(in project: WatchedProject) async throws -> [Incident] {
        var incidents: [Incident] = []
        var gids = Set<String>()
        var offset: String?
        var usedOffsets = Set<String>()
        var pages = 0

        repeat {
            var query = [
                URLQueryItem(name: "section", value: project.sections.detectadas),
                URLQueryItem(name: "completed_since", value: "now"),
                URLQueryItem(name: "opt_fields", value: AsanaClient.optFields),
                URLQueryItem(name: "limit", value: String(AsanaClient.pageLimit)),
            ]
            if let offset {
                query.append(URLQueryItem(name: "offset", value: offset))
            }
            let request = try makeRequest(method: "GET", path: "tasks", query: query)
            let data = try await perform(request)
            let page = try decode(TaskPageDTO.self, from: data)
            pages += 1

            // `completed_since=now` ya filtra; se descartan también las completadas por si acaso.
            for task in page.data where task.completed != true && !gids.contains(task.gid) {
                gids.insert(task.gid)
                incidents.append(makeIncident(from: task, project: project))
            }

            offset = page.nextPage?.offset
            // Protección ante un offset repetido o una paginación sin fin.
            if let next = offset {
                if usedOffsets.contains(next) || pages >= AsanaClient.maxPages { break }
                usedOffsets.insert(next)
            }
        } while offset != nil

        return incidents
    }

    // MARK: - Acciones

    /// Se asigna la tarea al usuario del token y pone Estado = "En curso".
    public func assignToMe(_ incident: Incident, config: NotchwatchConfig) async throws {
        let customFields: [String: Any] = [config.estadoFieldGid: config.estadoEnCursoOptionGid]
        let fields: [String: Any] = [
            "assignee": "me",
            "custom_fields": customFields,
        ]
        let request = try makeRequest(method: "PUT", path: "tasks/\(incident.gid)", body: ["data": fields])
        _ = try await perform(request)
    }

    /// Mueve la tarea a la sección "Verificación" del proyecto.
    public func moveToVerification(_ incident: Incident, project: WatchedProject) async throws {
        let fields: [String: Any] = ["task": incident.gid]
        let request = try makeRequest(
            method: "POST",
            path: "sections/\(project.sections.verificacion)/addTask",
            body: ["data": fields]
        )
        _ = try await perform(request)
    }

    /// Fija (o quita, con `nil`) la fecha de vencimiento "YYYY-MM-DD".
    public func setDueDate(_ incident: Incident, dueOn: String?) async throws {
        let value: Any
        if let dueOn {
            value = dueOn
        } else {
            value = NSNull()
        }
        let fields: [String: Any] = ["due_on": value]
        let request = try makeRequest(method: "PUT", path: "tasks/\(incident.gid)", body: ["data": fields])
        _ = try await perform(request)
    }

    /// Cambia la prioridad usando el campo de prioridad del proyecto (`.ninguna` la vacía).
    public func setPriority(_ incident: Incident, priority: IncidentPriority, project: WatchedProject) async throws {
        let value: Any
        if let optionGid = project.priorityField.options[priority] {
            value = optionGid
        } else {
            value = NSNull()
        }
        let customFields: [String: Any] = [project.priorityField.fieldGid: value]
        let fields: [String: Any] = ["custom_fields": customFields]
        let request = try makeRequest(method: "PUT", path: "tasks/\(incident.gid)", body: ["data": fields])
        _ = try await perform(request)
    }

    // MARK: - Mapeo

    /// Convierte una tarea de Asana en `Incident`.
    func makeIncident(from task: TaskDTO, project: WatchedProject) -> Incident {
        let fields = task.customFields ?? []
        let priorityOption = fields.first(where: { $0.gid == project.priorityField.fieldGid })?.enumValue?.gid
        let reporter = fields.first(where: { $0.gid == AsanaClient.reporterFieldGid })?.displayValue
        let module = fields.first(where: { $0.gid == AsanaClient.moduleFieldGid })?.displayValue

        return Incident(
            gid: task.gid,
            projectKey: project.key,
            projectName: project.name,
            name: task.name ?? "(sin título)",
            priority: project.priorityField.priority(forOptionGid: priorityOption),
            reporter: AsanaClient.nonEmpty(reporter),
            module: AsanaClient.nonEmpty(module),
            consoleErrors: ConsoleSummaryParser.errorCount(fromNotes: task.notes),
            // Si created_at no viene o no se entiende, se trata como antigua.
            createdAt: AsanaClient.parseDate(task.createdAt) ?? Date(timeIntervalSince1970: 0),
            dueOn: AsanaClient.nonEmpty(task.dueOn),
            assigneeName: AsanaClient.nonEmpty(task.assignee?.name),
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

    /// Devuelve nil para cadenas vacías o solo con espacios.
    static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
            throw AsanaError.invalidURL
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
            throw AsanaError.invalidURL
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
                throw AsanaError.decoding("No se pudo codificar el cuerpo: \(error)")
            }
        }
        return request
    }

    /// Envía la petición y traduce los códigos de estado a `AsanaError`.
    func perform(_ request: URLRequest) async throws -> Data {
        let result: (Data, HTTPURLResponse)
        do {
            result = try await transport.send(request)
        } catch let error as AsanaError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AsanaError.http(0, error.localizedDescription)
        }

        let (data, response) = result
        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw AsanaError.unauthorized
        case 429:
            let header = response.value(forHTTPHeaderField: "Retry-After")
            let retryAfter = header.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            throw AsanaError.rateLimited(retryAfter: retryAfter)
        default:
            throw AsanaError.http(response.statusCode, AsanaClient.errorMessage(from: data))
        }
    }

    /// Decodifica envolviendo los errores en `AsanaError.decoding`.
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AsanaError.decoding(String(describing: error))
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

/// Envoltorio genérico {"data": …}.
struct DataEnvelope<T: Decodable>: Decodable {
    let data: T
}

struct UserDTO: Decodable {
    let gid: String
    let name: String?
}

/// Página de tareas con `next_page` (null en la última).
struct TaskPageDTO: Decodable {
    let data: [TaskDTO]
    let nextPage: NextPageDTO?

    enum CodingKeys: String, CodingKey {
        case data
        case nextPage = "next_page"
    }
}

struct NextPageDTO: Decodable {
    let offset: String?
}

struct TaskDTO: Decodable {
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

struct AssigneeDTO: Decodable {
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
