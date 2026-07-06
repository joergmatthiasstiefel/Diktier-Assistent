import Foundation

enum ClaudeClientError: Error, LocalizedError {
    case missingAPIKey
    case network(Error)
    case badResponse(Int, String)
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Kein Anthropic API-Key hinterlegt. Bitte in den Einstellungen eintragen."
        case .network(let error):
            return "Keine Verbindung zur Claude API: \(error.localizedDescription)"
        case .badResponse(let code, let body):
            return "Claude API Fehler (\(code)): \(body.prefix(200))"
        case .emptyContent:
            return "Claude hat keinen Text zurückgegeben."
        }
    }
}

/// Schickt das Rohtranskript an die Anthropic Messages API und bekommt einen
/// geglätteten, ausformulierten Text zurück.
final class ClaudeClient {
    private let model = "claude-haiku-4-5-20251001"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private let systemPrompt = """
    Du bekommst ein rohes Sprache-zu-Text-Transkript auf Deutsch. Glätte es zu \
    einem sauberen, ausformulierten Text: Entferne Füllwörter, Versprecher und \
    Wiederholungen, korrigiere Grammatik und Zeichensetzung. Inhalt und \
    Bedeutung dürfen sich nicht ändern. Gib ausschließlich den bereinigten Text \
    zurück, ohne Anführungszeichen, Erklärungen oder Meta-Kommentare.
    """

    func cleanUp(transcript: String, apiKey: String, completion: @escaping (Result<String, ClaudeClientError>) -> Void) {
        guard !apiKey.isEmpty else {
            completion(.failure(.missingAPIKey))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": transcript]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.network(error)))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(error)))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(.badResponse(-1, "Keine Antwort erhalten")))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(.badResponse(http.statusCode, bodyText)))
                return
            }
            do {
                guard
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let content = json["content"] as? [[String: Any]],
                    let text = content.compactMap({ $0["text"] as? String }).first
                else {
                    completion(.failure(.emptyContent))
                    return
                }
                completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                completion(.failure(.network(error)))
            }
        }.resume()
    }
}
