import Foundation

/// Contenido de una notificación de macOS (sin depender de UserNotifications, para poder testearlo).
public struct NotificationPayload: Equatable, Sendable {
    /// Identificador de la incidencia, o `NotificationPlanner.summaryIdentifier` en el resumen.
    public var identifier: String
    /// "Urgente · Finanzas" o "3 incidencias nuevas".
    public var title: String
    /// Detalles en una línea; "" si no hay ninguno.
    public var subtitle: String
    public var body: String
    /// Hilo con el que el centro de notificaciones agrupa los avisos: id de la colección o el del resumen.
    public var threadIdentifier: String
    /// Incidencia a abrir al pulsar; nil en el resumen.
    public var incidentGid: String?
    /// Enlace a la tarea en Asana; nil en el resumen.
    public var url: URL?
    /// true si la notificación agrupa varias incidencias.
    public var isSummary: Bool

    public init(
        identifier: String,
        title: String,
        subtitle: String,
        body: String,
        threadIdentifier: String,
        incidentGid: String?,
        url: URL?,
        isSummary: Bool
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.threadIdentifier = threadIdentifier
        self.incidentGid = incidentGid
        self.url = url
        self.isSummary = isSummary
    }
}

/// Decide qué notificaciones mostrar para una tanda de incidencias nuevas. Los textos llegan
/// localizados en `strings`.
public enum NotificationPlanner {
    /// Identificador e hilo fijos del resumen: cada resumen nuevo sustituye al anterior.
    public static let summaryIdentifier = "notchwatch.summary"
    /// Máximo de notificaciones individuales por tanda; con más se muestra solo el resumen.
    public static let maxIndividual = 3

    /// Notificaciones de una tanda, de la más a la menos importante (prioridad desc y fecha desc).
    /// Sin incidencias, []. Una sola va siempre individual, aunque `asBatch`. Con `asBatch` o más de
    /// `maxIndividual`, solo el resumen; si no, una por incidencia. `asBatch` es la tanda de la primera
    /// lectura de la sesión: incidencias que ya estaban pendientes, así que su resumen dice «pendientes».
    public static func payloads(for incidents: [Incident], asBatch: Bool, strings: NotificationStrings) -> [NotificationPayload] {
        let ranked = IncidentDiffer.ordered(incidents)
        guard let top = ranked.first else { return [] }
        if ranked.count == 1 {
            return [payload(for: top, strings: strings)]
        }
        if asBatch || ranked.count > maxIndividual {
            return [summaryPayload(top: top, count: ranked.count, pendingAtStartup: asBatch, strings: strings)]
        }
        return ranked.map { payload(for: $0, strings: strings) }
    }

    /// Notificación de una incidencia: «Prioridad · Colección» como título, los detalles como subtítulo
    /// y el nombre como cuerpo. Se agrupa por colección y abre la tarea en la fuente.
    public static func payload(for incident: Incident, strings: NotificationStrings) -> NotificationPayload {
        NotificationPayload(
            identifier: incident.id,
            title: headline(for: incident, strings: strings),
            subtitle: subtitle(for: incident, strings: strings),
            body: incident.name,
            threadIdentifier: incident.collectionID,
            incidentGid: incident.id,
            url: incident.permalinkURL,
            isSummary: false
        )
    }

    /// Resumen de la tanda («3 incidencias nuevas», o «3 incidencias pendientes» al arrancar) que destaca
    /// la más importante; nil si no hay incidencias.
    public static func summary(
        for incidents: [Incident],
        pendingAtStartup: Bool = false,
        strings: NotificationStrings
    ) -> NotificationPayload? {
        guard let top = IncidentDiffer.ordered(incidents).first else { return nil }
        return summaryPayload(top: top, count: incidents.count, pendingAtStartup: pendingAtStartup, strings: strings)
    }

    /// «Reportada por Ana · Presupuestos · 2 errores de consola», solo con las partes que tienen valor.
    static func subtitle(for incident: Incident, strings: NotificationStrings) -> String {
        var parts: [String] = []
        if let reporter = Text.nonEmpty(incident.reporter) {
            parts.append(strings.reportedBy(reporter))
        }
        if let module = Text.nonEmpty(incident.module) {
            parts.append(module)
        }
        if let errors = incident.consoleErrors, errors > 0 {
            parts.append(strings.consoleErrors(errors))
        }
        return parts.joined(separator: " · ")
    }

    private static func headline(for incident: Incident, strings: NotificationStrings) -> String {
        "\(strings.priorityLabel(incident.priority)) · \(incident.collectionName)"
    }

    private static func summaryPayload(
        top: Incident,
        count: Int,
        pendingAtStartup: Bool,
        strings: NotificationStrings
    ) -> NotificationPayload {
        NotificationPayload(
            identifier: summaryIdentifier,
            title: pendingAtStartup ? strings.pendingIncidents(count) : strings.newIncidents(count),
            subtitle: strings.mostImportant(headline(for: top, strings: strings)),
            body: count > 1 ? strings.andMore(top.name, count - 1) : top.name,
            threadIdentifier: summaryIdentifier,
            incidentGid: nil,
            url: nil,
            isSummary: true
        )
    }
}
