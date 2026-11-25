import Foundation

/// Eigene Begriffe und feste Ersetzungen, gleiche Bedienung wie in EdiTalk
/// im Browser. Liegt in den UserDefaults, weil nichts davon geheim ist.
///
/// - Begriffe: je einer pro Zeile; Claude muss sie genau so schreiben.
/// - Ersetzungen: „gesprochen = geschrieben“, je eine pro Zeile. Sie gelten
///   in jedem Modus, auch ohne Glättung, und laufen vor dem Claude-Aufruf.
enum Woerterbuch {
    private static let termsKey = "woerterbuchBegriffe"
    private static let replacementsKey = "woerterbuchErsetzungen"

    struct Replacement: Equatable {
        let spoken: String
        let written: String
    }

    /// Der Text, wie er in den Einstellungen steht.
    static var termsText: String {
        get { UserDefaults.standard.string(forKey: termsKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: termsKey) }
    }

    static var replacementsText: String {
        get { UserDefaults.standard.string(forKey: replacementsKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: replacementsKey) }
    }

    static var terms: [String] {
        termsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Zeilen ohne Gleichheitszeichen oder mit leerer Seite werden übergangen.
    static var replacements: [Replacement] {
        parseReplacements(replacementsText)
    }

    static func parseReplacements(_ text: String) -> [Replacement] {
        text.components(separatedBy: .newlines).compactMap { line in
            guard let index = line.firstIndex(of: "=") else { return nil }
            let spoken = line[..<index].trimmingCharacters(in: .whitespaces)
            let written = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
            return spoken.isEmpty || written.isEmpty ? nil : Replacement(spoken: spoken, written: written)
        }
    }

    /// Alles, was Claude genau so schreiben muss: die Begriffe und die rechte
    /// Seite der Ersetzungen, ohne Doppelte.
    static var protectedTerms: [String] {
        var seen = Set<String>()
        return (terms + replacements.map(\.written)).filter { seen.insert($0.lowercased()).inserted }
    }

    static func applyReplacements(to text: String) -> String {
        applyReplacements(replacements, to: text)
    }

    /// Nur ganze Wörter, ohne Rücksicht auf Groß- und Kleinschreibung. Zwischen
    /// den Wörtern darf Leerraum oder ein Bindestrich stehen („n acht n“ und
    /// „N-acht-N“). Längere Regeln zuerst, damit kürzere sie nicht anschneiden.
    static func applyReplacements(_ rules: [Replacement], to text: String) -> String {
        var result = text
        for rule in rules.sorted(by: { $0.spoken.count > $1.spoken.count }) {
            let words = rule.spoken
                .components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-")))
                .filter { !$0.isEmpty }
                .map(NSRegularExpression.escapedPattern(for:))
            guard !words.isEmpty else { continue }
            let pattern = #"(?<![\p{L}\p{N}])"# + words.joined(separator: #"[\s-]+"#) + #"(?![\p{L}\p{N}])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.written)
            )
        }
        return result
    }
}
