import SwiftUI

/// Navigateur de bibliothèque : charge un index JSON de modules et permet
/// d'ajouter chaque module en un tap. URL par défaut = cufiy, éditable.
struct LibraryView: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss

    @State private var libraryURL: String = ModuleStore.defaultLibraries.first?.url ?? ""
    @State private var entries: [LibraryModuleEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var busyKey: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ModuleStore.defaultLibraries) { lib in
                        Button(lib.name) { libraryURL = lib.url; Task { await load() } }
                    }
                    HStack {
                        TextField("URL d'un index .json", text: $libraryURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.caption, design: .monospaced))
                        Button("Charger") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                } header: {
                    Text("Bibliothèque")
                }

                if let errorMessage {
                    Section { ErrorBanner(message: errorMessage).listRowInsets(EdgeInsets()) }
                }

                if !entries.isEmpty {
                    Section("Modules (\(entries.count))") {
                        ForEach(entries) { entry in
                            LibraryRow(
                                entry: entry,
                                installed: isInstalled(entry),
                                busy: busyKey == entry.installKey,
                                add: { Task { await add(entry) } }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Bibliothèques")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .overlay {
                if isLoading { ProgressView().controlSize(.large) }
            }
            .task { if entries.isEmpty { await load() } }
        }
    }

    private func isInstalled(_ entry: LibraryModuleEntry) -> Bool {
        store.modules.contains {
            $0.manifest.scriptUrl == entry.inlineManifest?.scriptUrl
                || $0.manifest.manifestUrl == entry.manifestURL
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let data = try await store.data(from: libraryURL)
            entries = try ModuleLibrary.parse(data)
            if entries.isEmpty { errorMessage = "Index chargé mais aucun module reconnu." }
        } catch {
            errorMessage = error.localizedDescription
            entries = []
        }
        isLoading = false
    }

    private func add(_ entry: LibraryModuleEntry) async {
        busyKey = entry.installKey
        do {
            if let manifest = entry.inlineManifest {
                try await store.add(manifest: manifest)
            } else if let url = entry.manifestURL {
                try await store.addByManifestURL(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        busyKey = nil
    }
}

private struct LibraryRow: View {
    let entry: LibraryModuleEntry
    let installed: Bool
    let busy: Bool
    let add: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: entry.icon, cornerRadius: 8)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    if let v = entry.version { Text("v\(v)") }
                    if let t = entry.type { Text("· \(t)") }
                    if let a = entry.author { Text("· \(a)") }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if busy {
                ProgressView()
            } else if installed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Ajouter", action: add)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
