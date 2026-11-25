import Foundation

/// Die letzten 20 Diktate, damit nach dem Einfügen nichts verloren ist.
/// Liegt in den UserDefaults dieser App auf diesem Mac und geht nirgendwohin.
enum Verlauf {
    struct Eintrag: Codable, Equatable {
        let zeit: Date
        let modus: String
        /// Was gesprochen wurde, nach den festen Ersetzungen.
        let wortgenau: String
        let ergebnis: String
    }

    private static let key = "verlauf"
    private static let maximum = 20

    static var eintraege: [Eintrag] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Eintrag].self, from: data) else { return [] }
        return list
    }

    static func hinzufuegen(modus: String, wortgenau: String, ergebnis: String) {
        var list = eintraege
        list.insert(Eintrag(zeit: Date(), modus: modus, wortgenau: wortgenau, ergebnis: ergebnis), at: 0)
        if let data = try? JSONEncoder().encode(Array(list.prefix(maximum))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func loeschen() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
