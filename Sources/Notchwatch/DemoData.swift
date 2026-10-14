import Foundation
import NotchwatchCore

/// Incidencias de ejemplo para el modo demo, las simulaciones de Ajustes y las capturas de CI.
enum DemoData {
    struct Template {
        let project: String
        let title: String
        let priority: IncidentPriority
        let reporter: String
        let module: String
        let consoleErrors: Int?
        let dueInDays: Int?
    }

    static let templates: [Template] = [
        Template(project: "finanzas", title: "La remesa SEPA de esta semana sale duplicada", priority: .urgente, reporter: "Ana", module: "sepa", consoleErrors: 5, dueInDays: 0),
        Template(project: "operaciones", title: "Traslado del jueves sin driver asignado", priority: .alta, reporter: "Javier Castelao", module: "transfers", consoleErrors: 1, dueInDays: 1),
        Template(project: "ventas", title: "El presupuesto no suma la noche extra en Roncesvalles", priority: .media, reporter: "Maricanto", module: "budgets", consoleErrors: 3, dueInDays: nil),
        Template(project: "mailing", title: "La plantilla de bienvenida no carga las imágenes", priority: .baja, reporter: "Nuria", module: "plantillas", consoleErrors: 2, dueInDays: 4),
        Template(project: "traslados", title: "El conductor no recibe el aviso de cambio de horario", priority: .alta, reporter: "Filipe", module: "drivers", consoleErrors: nil, dueInDays: nil),
        Template(project: "mitbc", title: "No puedo fichar la salida desde el portátil", priority: .baja, reporter: "Olalla", module: "jornada", consoleErrors: nil, dueInDays: nil),
        Template(project: "ventas", title: "Lead duplicado al importar desde RRSS", priority: .media, reporter: "Mila", module: "leads", consoleErrors: 1, dueInDays: 2),
        Template(project: "general", title: "Error 500 al abrir la reserva 145679", priority: .urgente, reporter: "Isolino", module: "reservations", consoleErrors: 4, dueInDays: nil),
    ]

    static func incident(from template: Template, createdAt: Date) -> Incident {
        let project = NotchwatchConfig.tubuencamino.projects.first { $0.key == template.project }
        let calendar = Calendar.current
        let due = template.dueInDays.flatMap { days in
            calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: createdAt))
        }
        return Incident(
            gid: "demo-\(UUID().uuidString)",
            projectKey: template.project,
            projectName: project?.name ?? template.project,
            name: template.title,
            priority: template.priority,
            reporter: template.reporter,
            module: template.module,
            consoleErrors: template.consoleErrors,
            createdAt: createdAt,
            dueOn: due.map { Formatters.isoDay($0) },
            assigneeName: nil,
            permalinkURL: nil
        )
    }

    /// Las cuatro primeras plantillas, creadas hace pocos minutos.
    static func initialIncidents(now: Date = Date()) -> [Incident] {
        templates.prefix(4).enumerated().map { offset, template in
            incident(from: template, createdAt: now.addingTimeInterval(-Double(offset + 1) * 140))
        }
    }

    static func randomIncident(now: Date = Date()) -> Incident {
        let template = templates.randomElement() ?? templates[0]
        return incident(from: template, createdAt: now)
    }

    /// Incidencia de prueba con la prioridad pedida (botón "Simular" de Ajustes).
    static func makeIncident(priority: IncidentPriority, now: Date = Date()) -> Incident {
        let base = templates.first { $0.priority == priority } ?? templates[0]
        var result = DemoData.incident(from: base, createdAt: now)
        result.name = "[Prueba] \(base.title)"
        result.priority = priority
        return result
    }

    /// Una por prioridad, para las capturas.
    static func sample(_ priority: IncidentPriority, now: Date = Date()) -> Incident {
        let base = templates.first { $0.priority == priority } ?? templates[0]
        return incident(from: base, createdAt: now.addingTimeInterval(-50))
    }
}
