import SwiftUI
import UIKit

/// Console de debug : console.log des modules, requêtes fetchv2, exceptions JS.
struct LogsView: View {
    @EnvironmentObject private var debugLog: DebugLog
    @State private var filter: LogKind?

    private var entries: [LogEntry] {
        guard let filter else { return debugLog.entries }
        return debugLog.entries.filter { $0.kind == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filtre", selection: $filter) {
                Text("Tout").tag(LogKind?.none)
                Text("Console").tag(LogKind?.some(.console))
                Text("Réseau").tag(LogKind?.some(.fetch))
                Text("Erreurs").tag(LogKind?.some(.error))
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)

            if entries.isEmpty {
                Spacer()
                Text("Aucun log pour le moment.").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(entries) { entry in
                                LogRow(entry: entry).id(entry.id)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: debugLog.entries.count) { _ in
                        if let last = entries.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = entries.map(\.plain).joined(separator: "\n")
                } label: { Image(systemName: "doc.on.doc") }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .destructive) { debugLog.clear() } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Image(systemName: entry.kind.icon).foregroundStyle(entry.kind.color)
                Text(entry.timeString).font(.caption2).foregroundStyle(.secondary)
                if let m = entry.module {
                    Text(m).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(entry.kind == .error ? .red : .primary)
                .textSelection(.enabled)
            if let detail = entry.detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private extension LogEntry {
    var plain: String {
        var line = "[\(timeString)] \(kind.rawValue.uppercased())"
        if let module { line += " (\(module))" }
        line += ": \(message)"
        if let detail { line += " — \(detail)" }
        return line
    }
}

private extension LogKind {
    var icon: String {
        switch self {
        case .console: return "text.bubble"
        case .fetch: return "network"
        case .error: return "exclamationmark.triangle"
        case .info: return "info.circle"
        }
    }
    var color: Color {
        switch self {
        case .console: return .secondary
        case .fetch: return .blue
        case .error: return .red
        case .info: return .green
        }
    }
}
