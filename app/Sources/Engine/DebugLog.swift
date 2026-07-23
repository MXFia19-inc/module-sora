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
    @Published private(set) var errorCount: Int = 0

    private let maxEntries = 1000

    // Coalescence : les appends d'un même cycle de run loop sont regroupés en une
    // seule mise à jour @Published → évite les micro-freezes quand un module
    // journalise / ping périodiquement.
    private var pending: [LogEntry] = []
    private var flushScheduled = false

    func append(_ kind: LogKind, _ message: String, module: String? = nil, detail: String? = nil) {
        let entry = LogEntry(date: Date(), kind: kind, module: module, message: message, detail: detail)
        if Thread.isMainThread {
            enqueue(entry)
        } else {
            DispatchQueue.main.async { [weak self] in self?.enqueue(entry) }
        }
    }

    private func enqueue(_ entry: LogEntry) {
        pending.append(entry)
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    private func flush() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let added = pending
        pending.removeAll()
        entries.append(contentsOf: added)
        errorCount += added.reduce(0) { $0 + ($1.kind == .error ? 1 : 0) }
        if entries.count > maxEntries {
            let overflow = entries.count - maxEntries
            errorCount -= entries.prefix(overflow).reduce(0) { $0 + ($1.kind == .error ? 1 : 0) }
            entries.removeFirst(overflow)
        }
    }

    func clear() {
        pending.removeAll()
        entries.removeAll()
        errorCount = 0
    }

    func entries(for module: String?) -> [LogEntry] {
        guard let module else { return entries }
        return entries.filter { $0.module == module }
    }
}
