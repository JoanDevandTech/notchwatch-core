import Foundation

/// Propone la configuración de un proyecto de Asana a partir de los nombres de sus secciones y
/// campos. Las comparaciones ignoran mayúsculas y acentos.
public enum AsanaConfigurator {
    static let detectedHints = ["detect", "nuev", "inbox", "pendiente", "to do", "backlog"]
    static let resolvedHints = ["verific", "resuel", "done", "hech", "solucion"]
    static let priorityHints = ["priori"]
    static let statusHints = ["estado", "status"]
    static let inProgressHints = ["en curso", "in progress", "doing"]
    static let solvedHints = ["solucion", "resuel", "resolved", "done", "hech"]
    static let reporterHints = ["report"]
    static let moduleHints = ["modulo", "module"]
    static let nameSuffixes = [" incidencias", " incidents"]

    /// Estilos fijos que se reparten entre proyectos según el nombre.
    public static let styles: [CollectionStyle] = [
        CollectionStyle(symbol: "chart.bar.fill", colorHex: "#DFB47D"),
        CollectionStyle(symbol: "creditcard.fill", colorHex: "#E78580"),
        CollectionStyle(symbol: "shippingbox.fill", colorHex: "#85BAA8"),
        CollectionStyle(symbol: "car.fill", colorHex: "#D8C790"),
        CollectionStyle(symbol: "envelope.fill", colorHex: "#B3CBEC"),
        CollectionStyle(symbol: "person.crop.circle.fill", colorHex: "#C9A7E0"),
        CollectionStyle(symbol: "flame.fill", colorHex: "#E78580"),
        CollectionStyle(symbol: "square.stack.3d.up.fill", colorHex: "#A8B7C8"),
    ]

    public static func suggest(for layout: AsanaProjectLayout, sourceID: String) -> AsanaProjectConfig {
        let name = displayName(layout.project.name)
        let collection = WatchedCollection(
            id: WatchedCollection.makeID(sourceID: sourceID, key: slug(name)),
            name: name,
            style: style(forName: layout.project.name)
        )
        let detected = section(in: layout.sections, matching: detectedHints) ?? layout.sections.first
        return AsanaProjectConfig(
            collection: collection,
            projectGid: layout.project.gid,
            projectName: layout.project.name,
            detectedSectionGid: detected?.gid ?? "",
            resolvedSectionGid: section(in: layout.sections, matching: resolvedHints)?.gid,
            priorityField: priorityField(in: layout.fields),
            statusField: statusField(in: layout.fields),
            reporterFieldGid: textField(in: layout.fields, matching: reporterHints)?.gid,
            moduleFieldGid: textField(in: layout.fields, matching: moduleHints)?.gid
        )
    }

    /// Slug ASCII: minúsculas, sin acentos, palabras separadas por guiones.
    public static func slug(_ name: String) -> String {
        var slug = ""
        var pendingSeparator = false
        for scalar in fold(displayName(name)).unicodeScalars {
            if (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) {
                if pendingSeparator && !slug.isEmpty {
                    slug.append("-")
                }
                pendingSeparator = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        return slug
    }

    /// Nombre corto: sin los sufijos « Incidencias» / « Incidents».
    static func displayName(_ projectName: String) -> String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = fold(trimmed)
        for suffix in nameSuffixes where folded.hasSuffix(suffix) {
            let cut = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return cut.isEmpty ? trimmed : cut
        }
        return trimmed
    }

    /// Estilo estable para un nombre: índice por hash djb2 (no `hashValue`, que cambia en cada proceso).
    static func style(forName name: String) -> CollectionStyle {
        var hash: UInt32 = 5381
        for byte in fold(name).utf8 {
            hash = (hash &* 33) &+ UInt32(byte)
        }
        return styles[Int(hash % UInt32(styles.count))]
    }

    // MARK: - Heurísticas

    static func section(in sections: [AsanaSection], matching hints: [String]) -> AsanaSection? {
        sections.first { contains($0.name, anyOf: hints) }
    }

    static func priorityField(in fields: [AsanaCustomField]) -> PriorityField? {
        guard let field = enumField(in: fields, matching: priorityHints) else { return nil }
        var options: [IncidentPriority: String] = [:]
        for option in field.options {
            guard let priority = priority(forOptionName: option.name), options[priority] == nil else { continue }
            options[priority] = option.gid
        }
        return PriorityField(fieldGid: field.gid, options: options)
    }

    static func priority(forOptionName name: String) -> IncidentPriority? {
        if contains(name, anyOf: ["urgente", "critic", "incidencia"]) { return .urgente }
        if contains(name, anyOf: ["alta", "high"]) { return .alta }
        if contains(name, anyOf: ["media", "medium", "normal"]) { return .media }
        if contains(name, anyOf: ["baja", "low"]) { return .baja }
        return nil
    }

    static func statusField(in fields: [AsanaCustomField]) -> StatusField? {
        guard
            let field = enumField(in: fields, matching: statusHints),
            let option = field.options.first(where: { contains($0.name, anyOf: inProgressHints) })
        else { return nil }
        let solved = field.options.first(where: { contains($0.name, anyOf: solvedHints) })
        return StatusField(fieldGid: field.gid, inProgressOptionGid: option.gid, solvedOptionGid: solved?.gid)
    }

    static func enumField(in fields: [AsanaCustomField], matching hints: [String]) -> AsanaCustomField? {
        fields.first { $0.type == "enum" && contains($0.name, anyOf: hints) }
    }

    static func textField(in fields: [AsanaCustomField], matching hints: [String]) -> AsanaCustomField? {
        fields.first { $0.type == "text" && contains($0.name, anyOf: hints) }
    }

    static func contains(_ text: String, anyOf hints: [String]) -> Bool {
        let folded = fold(text)
        return hints.contains { folded.contains($0) }
    }

    /// Minúsculas sin diacríticos («Verificación» → «verificacion»).
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }
}
