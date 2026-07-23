import Foundation
import Combine

enum LogKind: String {
    case console
    case fetch
    case error
    case info
}

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let kind: LogKind
    let module: String?
    let message: String
    /// Détail optionnel (corps de requête, statut, durée…).
    let detail: String?

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }
}

/// Buffer observable des logs (console.log des modules, requêtes fetchv2, exceptions JS).
///
/// Non isolé au main, mais toutes les écritures sont dispatchées sur le main par
/// l'appelant (le moteur JS notamment), pour rester compatible avec `@Published`.
final class DebugLog: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 1000

    var errorCount: Int { entries.filter { $0.kind == .error }.count }

    func append(_ kind: LogKind, _ message: String, module: String? = nil, detail: String? = nil) {
        let entry = LogEntry(date: Date(), kind: kind, module: module, message: message, detail: detail)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    func entries(for module: String?) -> [LogEntry] {
        guard let module else { return entries }
        return entries.filter { $0.module == module }
    }
}
