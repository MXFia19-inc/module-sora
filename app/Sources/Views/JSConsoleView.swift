import SwiftUI
import UIKit

/// Une entrée de la console : l'expression saisie et le résultat.
private struct ConsoleEntry: Identifiable {
    let id = UUID()
    let input: String
    let output: String
    let isError: Bool
    let ms: Int
}

/// Console JS interactive : exécute du code dans le contexte VIVANT du module,
/// avec ses variables globales et ses fonctions déjà chargées.
struct JSConsoleView: View {
    let runner: ModuleRunner?
    let moduleName: String

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var entries: [ConsoleEntry] = []
    @State private var isRunning = false
    @FocusState private var inputFocused: Bool

    /// Raccourcis vers les fonctions du contrat.
    private let snippets = [
        "await searchResults(\"one piece\")",
        "await extractDetails(\"\")",
        "await extractEpisodes(\"\")",
        "await extractStreamUrl(\"\")",
        "Object.keys(globalThis).filter(k => typeof globalThis[k] === 'function')",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if entries.isEmpty {
                                Text(L("Type JavaScript to run it inside the module's context."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                            }
                            ForEach(entries) { entry in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("› \(entry.input)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(Color.accentColor)
                                    Text(entry.output)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(entry.isError ? .red : .primary)
                                        .textSelection(.enabled)
                                    Text("\(entry.ms) ms")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = entry.output
                                    } label: { Label(L("Copy"), systemImage: "doc.on.doc") }
                                    Button {
                                        input = entry.input
                                    } label: { Label(L("Reuse"), systemImage: "arrow.uturn.left") }
                                }
                                .id(entry.id)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: entries.count) { _ in
                        if let last = entries.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }

                Divider()

                // Raccourcis
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(snippets, id: \.self) { snippet in
                            Button {
                                input = snippet
                                inputFocused = true
                            } label: {
                                Text(snippet.count > 28 ? String(snippet.prefix(28)) + "…" : snippet)
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.secondary.opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }

                HStack(spacing: 8) {
                    TextField(L("JS expression…"), text: $input, axis: .vertical)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1...5)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($inputFocused)
                    Button {
                        run()
                    } label: {
                        Image(systemName: isRunning ? "hourglass" : "play.fill")
                    }
                    .disabled(isRunning || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("\(L("Console")) · \(moduleName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(L("Close")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { entries.removeAll() } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(entries.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Done")) { inputFocused = false }
                }
            }
        }
    }

    private func run() {
        guard let runner else {
            entries.append(ConsoleEntry(input: input, output: L("Module not loaded."),
                                        isError: true, ms: 0))
            return
        }
        let code = input
        input = ""
        isRunning = true
        let started = Date()
        Task {
            do {
                let output = try await runner.eval(code)
                entries.append(ConsoleEntry(input: code, output: output.isEmpty ? "undefined" : output,
                                            isError: false,
                                            ms: Int(Date().timeIntervalSince(started) * 1000)))
            } catch {
                entries.append(ConsoleEntry(input: code, output: error.localizedDescription,
                                            isError: true,
                                            ms: Int(Date().timeIntervalSince(started) * 1000)))
            }
            isRunning = false
        }
    }
}
