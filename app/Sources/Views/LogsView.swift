import SwiftUI
import UIKit

/// Console de debug : console.log des modules, requêtes fetchv2, exceptions JS.
struct LogsView: View {
    @EnvironmentObject private var debugLog: DebugLog
    @State private var filter: LogKind?
    @State private var moduleFilter: String?
    @State private var searchText = ""
    @State private var replayRequest: LoggedRequest?

    /// Modules distincts présents dans les logs.
    private var modules: [String] {
        Array(Set(debugLog.entries.compactMap { $0.module })).sorted()
    }

    private var entries: [LogEntry] {
        debugLog.entries.filter { entry in
            // Filtre par type ("Réseau" inclut les requêtes ET les bloquées).
            let kindOK: Bool
            switch filter {
            case nil: kindOK = true
            case .fetch: kindOK = (entry.kind == .fetch || entry.kind == .blocked)
            case let f?: kindOK = entry.kind == f
            }
            guard kindOK else { return false }
            if let moduleFilter, entry.module != moduleFilter { return false }
            if !searchText.isEmpty {
                let hay = "\(entry.message) \(entry.detail ?? "") \(entry.module ?? "")".lowercased()
                if !hay.contains(searchText.lowercased()) { return false }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("Filter"), selection: $filter) {
                Text(L("All")).tag(LogKind?.none)
                Text(L("Console")).tag(LogKind?.some(.console))
                Text(L("Network")).tag(LogKind?.some(.fetch))
                Text(L("Errors")).tag(LogKind?.some(.error))
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)

            if entries.isEmpty {
                Spacer()
                Text(L("No log.")).foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(entries) { entry in
                                LogRow(entry: entry, onReplay: { replayRequest = entry.request })
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: debugLog.entries.count) { _ in
                        if searchText.isEmpty, let last = entries.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Logs"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L("Filter (text, URL, HTTP code…)"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .destructive) { debugLog.clear() } label: {
                    Image(systemName: "trash")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(L("Module"), selection: $moduleFilter) {
                        Text(L("All modules")).tag(String?.none)
                        ForEach(modules, id: \.self) { m in Text(m).tag(String?.some(m)) }
                    }
                    Button {
                        UIPasteboard.general.string = entries.map(\.plain).joined(separator: "\n")
                    } label: { Label(L("Copy all (filtered)"), systemImage: "doc.on.doc") }
                } label: {
                    Image(systemName: moduleFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .sheet(item: $replayRequest) { request in
            RequestReplayView(request: request)
        }
    }
}

extension LoggedRequest: Identifiable {
    var id: String { "\(method)|\(url)|\(headers.count)|\(body?.count ?? 0)" }
}

private struct LogRow: View {
    let entry: LogEntry
    var onReplay: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Image(systemName: entry.kind.icon).foregroundStyle(entry.kind.color)
                Text(entry.timeString).font(.caption2).foregroundStyle(.secondary)
                if let m = entry.module {
                    Text(m).font(.caption2).foregroundStyle(.tertiary)
                }
                if entry.kind == .blocked {
                    Text(L("BLOCKED")).font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
            }
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(entry.kind == .error ? .red : (entry.kind == .blocked ? .orange : .primary))
            if let detail = entry.detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.plain
            } label: { Label(L("Copy this log"), systemImage: "doc.on.doc") }
            Button {
                UIPasteboard.general.string = entry.message
            } label: { Label(L("Copy the message only"), systemImage: "text.quote") }
            if entry.request != nil {
                Button {
                    onReplay()
                } label: { Label(L("Replay the request"), systemImage: "arrow.clockwise.circle") }
            }
        }
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
        case .blocked: return "hand.raised.fill"
        }
    }
    var color: Color {
        switch self {
        case .console: return .secondary
        case .fetch: return .blue
        case .error: return .red
        case .info: return .green
        case .blocked: return .orange
        }
    }
}

/// Rejoue une requête `fetchv2` capturée et affiche la réponse brute.
struct RequestReplayView: View {
    let request: LoggedRequest
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var status: Int?
    @State private var responseHeaders: [String: String] = [:]
    @State private var responseBody = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section(L("Request")) {
                    LabeledContent(L("Method"), value: request.method)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("URL").font(.caption).foregroundStyle(.secondary)
                        Text(request.url).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    }
                    if !request.headers.isEmpty {
                        DisclosureGroup("\(L("Headers")) (\(request.headers.count))") {
                            ForEach(request.headers.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                                Text("\(k): \(v)").font(.system(.caption2, design: .monospaced))
                            }
                        }
                    }
                }

                if let status {
                    Section(L("Response")) {
                        HStack {
                            Text(L("Status"))
                            Spacer()
                            Text("\(status)")
                                .foregroundStyle((200...299).contains(status) ? .green : .red)
                        }
                        Text("\(responseBody.count) \(L("characters"))").font(.caption2).foregroundStyle(.secondary)
                    }
                    Section(L("Body")) {
                        ScrollView(.horizontal) {
                            Text(responseBody.isEmpty ? L("(empty)") : responseBody)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                if let errorMessage {
                    Section { ErrorBanner(message: errorMessage).listRowInsets(EdgeInsets()) }
                }
            }
            .navigationTitle(L("Replay"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(L("Close")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = responseBody
                    } label: { Image(systemName: "doc.on.doc") }
                        .disabled(responseBody.isEmpty)
                }
            }
            .overlay { if isLoading { ProgressView().controlSize(.large) } }
            .task { await replay() }
        }
    }

    private func replay() async {
        isLoading = true
        errorMessage = nil
        do {
            guard let url = URL(string: request.url) else { throw URLError(.badURL) }
            let resp = try await NetworkFetch.perform(
                url: url, headers: request.headers, method: request.method,
                body: request.body, followRedirects: true
            )
            status = resp.status
            responseHeaders = resp.headers
            responseBody = String(data: resp.body, encoding: .utf8) ?? String(decoding: resp.body, as: UTF8.self)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
