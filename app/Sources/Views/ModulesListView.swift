import SwiftUI
import UniformTypeIdentifiers

/// Écran principal : liste des modules installés + ajout (URL, rapide, fichier).
struct ModulesListView: View {
    @EnvironmentObject private var store: ModuleStore

    @State private var showAddURL = false
    @State private var showQuickAdd = false
    @State private var showLibrary = false
    @State private var showPaste = false
    @State private var showImporter = false
    @State private var showDeleteAll = false
    @State private var urlText = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var search = ""

    /// Modules filtrés par la recherche, épinglés d'abord puis par nom.
    private var displayed: [LoadedModule] {
        let filtered = search.isEmpty
            ? store.modules
            : store.modules.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return filtered.sorted { a, b in
            let pa = store.pinned.contains(a.id), pb = store.pinned.contains(b.id)
            if pa != pb { return pa }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if store.modules.isEmpty {
                ContentUnavailableViewCompat(
                    title: "Aucun module",
                    systemImage: "puzzlepiece.extension",
                    description: "Ajoutez un module par URL, via une bibliothèque (cufiy…), la liste Luna, ou un fichier."
                )
            }
            ForEach(displayed) { module in
                NavigationLink(value: module) {
                    ModuleRow(module: module, pinned: store.isPinned(module))
                }
                .swipeActions(edge: .leading) {
                    Button {
                        store.togglePin(module)
                    } label: {
                        Label(store.isPinned(module) ? "Désépingler" : "Épingler",
                              systemImage: store.isPinned(module) ? "pin.slash" : "pin")
                    }
                    .tint(.yellow)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.remove(module)
                    } label: { Label("Supprimer", systemImage: "trash") }
                    Button {
                        Task { await refresh(module) }
                    } label: { Label("Rafraîchir", systemImage: "arrow.clockwise") }
                    .tint(.blue)
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Rechercher un module")
        .navigationTitle("Modules")
        .navigationDestination(for: LoadedModule.self) { module in
            ModuleTestView(module: module)
        }
        .toolbar {
            if !store.modules.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            Task { await refreshAll() }
                        } label: { Label("Tout rafraîchir", systemImage: "arrow.clockwise") }
                        Button(role: .destructive) {
                            showDeleteAll = true
                        } label: { Label("Tout supprimer", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAddURL = true } label: { Label("Ajouter par URL", systemImage: "link") }
                    Button { showLibrary = true } label: { Label("Bibliothèques (cufiy…)", systemImage: "books.vertical") }
                    Button { showQuickAdd = true } label: { Label("Modules Luna (MXFia19)", systemImage: "star") }
                    Button { showPaste = true } label: { Label("Coller du code (local)", systemImage: "curlybraces.square") }
                    Button { showImporter = true } label: { Label("Importer un fichier", systemImage: "folder") }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if busy { ProgressView().controlSize(.large) }
        }
        .alert("Erreur", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Ajouter par URL", isPresented: $showAddURL) {
            TextField("https://…/module.json", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Ajouter") { Task { await addByURL() } }
            Button("Annuler", role: .cancel) { urlText = "" }
        } message: {
            Text("Collez l'URL du manifest .json du module.")
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView()
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView()
        }
        .sheet(isPresented: $showPaste) {
            PasteModuleView()
        }
        .confirmationDialog("Supprimer tous les modules ?", isPresented: $showDeleteAll, titleVisibility: .visible) {
            Button("Tout supprimer (\(store.modules.count))", role: .destructive) { store.removeAll() }
            Button("Annuler", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .javaScript, .item],
            allowsMultipleSelection: true
        ) { result in
            Task { await importFiles(result) }
        }
    }

    // MARK: - Actions

    private func addByURL() async {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        urlText = ""
        guard !url.isEmpty else { return }
        busy = true
        do { try await store.addByManifestURL(url) }
        catch { errorMessage = error.localizedDescription }
        busy = false
    }

    private func refresh(_ module: LoadedModule) async {
        busy = true
        do { try await store.refresh(module) }
        catch { errorMessage = error.localizedDescription }
        busy = false
    }

    private func refreshAll() async {
        busy = true
        for module in store.modules {
            // Ignore les modules locaux (pas d'URL source).
            guard module.manifest.manifestUrl != nil || module.manifest.scriptUrl.hasPrefix("http") else { continue }
            do { try await store.refresh(module) }
            catch { errorMessage = error.localizedDescription }
        }
        busy = false
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            var manifestData: Data?
            var scriptData: Data?
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if url.pathExtension.lowercased() == "json" { manifestData = data }
                else if url.pathExtension.lowercased() == "js" { scriptData = data }
            }
            guard let manifestData else {
                errorMessage = "Sélectionnez le fichier .json (et son .js) du module."
                return
            }
            // Si le .js n'est pas fourni, on le télécharge depuis scriptUrl.
            if let scriptData {
                _ = try store.addLocal(manifestData: manifestData, scriptData: scriptData)
            } else if let manifest = try? JSONDecoder().decode(ModuleManifest.self, from: manifestData),
                      let scriptURL = URL(string: manifest.scriptUrl) {
                let (data, _) = try await URLSession.shared.data(from: scriptURL)
                _ = try store.addLocal(manifestData: manifestData, scriptData: data)
            } else {
                errorMessage = "Ajoutez aussi le fichier .js du module."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Ligne d'un module dans la liste.
private struct ModuleRow: View {
    let module: LoadedModule
    var pinned: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: module.manifest.iconUrl, cornerRadius: 8)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                    Text(module.name).font(.headline)
                }
                HStack(spacing: 6) {
                    Text("v\(module.manifest.version)")
                    if let lang = module.manifest.language { Text("· \(lang)") }
                    if let type = module.manifest.type { Text("· \(type)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Liste rapide des 8 modules connus.
private struct QuickAddView: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    @State private var busyId: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(ModuleStore.defaults) { def in
                HStack {
                    Text(def.name.capitalized)
                    Spacer()
                    if busyId == def.id {
                        ProgressView()
                    } else if store.modules.contains(where: { $0.manifest.manifestUrl == def.manifestUrl }) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Ajouter") { Task { await add(def) } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
            .navigationTitle("Modules Luna")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .alert("Erreur", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func add(_ def: DefaultModule) async {
        busyId = def.id
        do { try await store.addByManifestURL(def.manifestUrl) }
        catch { errorMessage = error.localizedDescription }
        busyId = nil
    }
}
