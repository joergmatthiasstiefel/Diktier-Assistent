import Foundation

/// Prüft, ob Claude das Diktat bearbeitet hat, statt darauf zu antworten.
/// Gleiche Regeln wie in EdiTalk im Browser, nach dem Vorbild von Blitztext
/// (RewriteGuard.swift, MIT-Lizenz). Bewusst eng: Abgelehnt wird nur, was
/// eindeutig keine Bearbeitung ist, nie eine freie Umformulierung.
enum RewriteGuard {
    enum Problem: Error, Equatable {
        case empty
        case brokenFrame
        case refusal

        var message: String {
            switch self {
            case .empty: return "Claude hat keinen Text zurückgegeben."
            case .brokenFrame: return "Claude hat den Text nicht sauber bearbeitet."
            case .refusal: return "Claude hat auf das Diktat geantwortet, statt es zu bearbeiten."
            }
        }
    }

    private static let tagPattern = try! NSRegularExpression(pattern: #"<\s*/?\s*diktat\s*>"#, options: [.caseInsensitive])

    /// Die Markierungen dürfen nicht aus dem Diktat selbst kommen, sonst ließe
    /// sich der Rahmen mit einem gesprochenen „</diktat>“ aufbrechen.
    static func withoutTags(_ text: String) -> String {
        tagPattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    /// Der bereinigte Text, oder ein Fehler, wenn er keine Bearbeitung ist.
    static func checked(_ output: String, source: String) -> Result<String, Problem> {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let wrapped = try? NSRegularExpression(pattern: #"^<\s*diktat\s*>([\s\S]*)<\s*/\s*diktat\s*>$"#, options: [.caseInsensitive])
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let inner = Range(wrapped.range(at: 1), in: text) {
            text = text[inner].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.isEmpty { return .failure(.empty) }
        if withoutTags(text) != text { return .failure(.brokenFrame) }
        // Eine Absage zählt nur, wenn sie nicht schon im Diktat stand:
        // „ich kann dir dabei leider nicht helfen“ darf man diktieren.
        if containsRefusal(text), !containsRefusal(source) { return .failure(.refusal) }
        return .success(text)
    }

    private static let refusalPatterns: [NSRegularExpression] = [
        #"\bich kann (dir|dich|ihnen|euch)\b[^.!?\n]{0,40}?\bnicht\b[^.!?\n]{0,40}?\b(helfen|unterstützen|behilflich|weiterhelfen|beantworten)"#,
        #"\bkann ich (dir|dich|ihnen|euch)\b[^.!?\n]{0,40}?\bnicht\b[^.!?\n]{0,40}?\b(helfen|unterstützen|behilflich|weiterhelfen|beantworten)"#,
        #"\bes tut mir leid,? (aber )?ich (kann|darf)\b"#,
        #"\bals (ki|künstliche intelligenz|sprachmodell|ki-modell|ki-assistent)\b"#,
        #"\bich bin (nur )?ein (ki|sprachmodell|ki-modell|ki-assistent)\b"#,
        #"\bi (can't|cannot|can not|am unable to|'m unable to|am not able to) (help|assist)\b"#,
        #"\bi'm sorry,? but i (can't|cannot)\b"#,
        #"\bas an ai\b"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func containsRefusal(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "’", with: "'")
        let range = NSRange(normalized.startIndex..., in: normalized)
        return refusalPatterns.contains { $0.firstMatch(in: normalized, range: range) != nil }
    }
}
