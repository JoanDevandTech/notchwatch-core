import Foundation

/// Extrae el nº de errores de consola del resumen que acompaña a la incidencia.
public enum ConsoleSummaryParser {
    /// "Errores consola: 7/10" -> 7. Tolera "Errores de consola", negritas markdown y mayúsculas.
    public static func errorCount(fromNotes notes: String?) -> Int? {
        guard let notes, !notes.isEmpty else { return nil }
        let pattern = #"errores\s+(?:de\s+)?consola[*_\s]*:[*_\s]*(\d+)"#
        // NSRegularExpression no es Sendable: se crea en cada llamada.
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(notes.startIndex..<notes.endIndex, in: notes)
        guard
            let match = regex.firstMatch(in: notes, options: [], range: range),
            match.numberOfRanges > 1,
            let captured = Range(match.range(at: 1), in: notes)
        else {
            return nil
        }
        return Int(notes[captured])
    }
}
