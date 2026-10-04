import SwiftUI

/// Dépôts de modules : on colle le lien d'un dépôt (GitHub, Gitea…) et l'app y
/// trouve tous les modules qu'il contient, installables un par un ou d'un coup.
struct RepoListView: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss

    @State private var newURL = ""
    @State private var errorMessage: String?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack {
                        TextField("https://github.com/owner/repo", text: $newURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.system(.caption, design: .monospaced))
                            .onSubmit { addRepo() }
                        Button(L("Add")) { addRepo() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text(L("Add a repository"))
                } footer: {
                    Text(L("GitHub or Gitea link. Every module in the repository is listed: each .json manifest next to a .js file. A …/tree/<branch>/<folder> link limits the scan to that folder."))
                }

                if let errorMessage {
                    Section { ErrorBanner(message: errorMessage).listRowInsets(EdgeInsets()) }
                }

                Section {
                    if store.repos.isEmpty {
                        Text(L("No repository")).foregroundStyle(.secondary)
                    }
                    ForEach(store.repos, id: \.self) { url in
                        NavigationLink(value: url) { RepoRow(url: url) }
                    }
                    .onDelete { offsets in
                        let urls = offsets.map { store.repos[$0] }
                        for url in urls { store.removeRepo(url) }
                    }
                } header: {
                    Text(L("Repositories"))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("Repositories"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { url in
                RepoDetailView(repoURL: url)
            }
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L("Close")) { dismiss() } }
            }
        }
    }

    private func addRepo() {
        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        guard ModuleRepoRef.parse(url) != nil else {
            errorMessage = L("Unrecognized repository link.")
            return
        }
        errorMessage = nil
        if !store.addRepo(url) {
            errorMessage = L("This repository is already in the list.")
        }
        newURL = ""
        path.append(url)
    }
}

/// Ligne d'un dépôt enregistré.
private struct RepoRow: View {
    let url: String

    private var title: String {
        ModuleRepoRef.parse(url)?.displayName ?? url
    }

    /// Hébergeur, et branche si le lien en impose une.
    private var subtitle: String {
        guard let ref = ModuleRepoRef.parse(url) else { return url }
        if let branch = ref.branch { return "\(ref.host) · \(branch)" }
        return ref.host
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Contenu d'un dépôt : ses modules, avec leur état d'installation.
struct RepoDetailView: View {
    @EnvironmentObject private var store: ModuleStore
    let repoURL: String

    @State private var entries: [RepoModuleEntry] = []
    @State private var truncated = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var busyIDs: Set<String> = []
    @State private var bulkDone = 0
    @State private var bulkTotal = 0
    @State private var searchText = ""
    @State private var languageFilter: String?

    private var ref: ModuleRepoRef? { ModuleRepoRef.parse(repoURL) }

    private var languages: [String] {
        Array(Set(entries.compactMap { $0.manifest.language })).sorted()
    }

    private var filtered: [RepoModuleEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return entries
            .filter { languageFilter == nil || $0.manifest.language == languageFilter }
            .filter { entry in
                guard !query.isEmpty else { return true }
                let m = entry.manifest
                let hay = "\(m.sourceName) \(m.author?.name ?? "") \(m.type ?? "") \(m.language ?? "") \(entry.path)"
                return hay.lowercased().contains(query)
            }
    }

    /// Modules pas encore installés.
    private var notInstalled: [RepoModuleEntry] {
        entries.filter { store.installed(for: $0) == nil }
    }

    /// Modules installés dont la version diffère de celle du dépôt.
    private var outdated: [RepoModuleEntry] {
        entries.filter { entry in
            guard let module = store.installed(for: entry) else { return false }
            return module.manifest.version != entry.manifest.version
        }
    }

    private var isBusy: Bool { isLoading || bulkTotal > 0 }

    var body: some View {
        List {
            if !entries.isEmpty {
                Section {
                    Text(Lf("%lld modules · %lld installed · %lld update(s)",
                            entries.count, entries.count - notInstalled.count, outdated.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button {
                            Task { await installAll(notInstalled) }
                        } label: {
                            Label(L("Install all"), systemImage: "square.and.arrow.down.on.square")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(notInstalled.isEmpty || isBusy)

                        Button {
                            Task { await installAll(outdated) }
                        } label: {
                            Label(L("Update all"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .disabled(outdated.isEmpty || isBusy)
                    }
                    .controlSize(.small)
                } footer: {
                    if truncated {
                        Text(L("The repository is too large: the host truncated its file list, some modules may be missing."))
                    }
                }
            }

            if let errorMessage {
                Section { ErrorBanner(message: errorMessage).listRowInsets(EdgeInsets()) }
            }

            if !entries.isEmpty {
                Section {
                    ForEach(filtered) { entry in
                        RepoModuleRow(
                            entry: entry,
                            installedVersion: store.installed(for: entry)?.manifest.version,
                            busy: busyIDs.contains(entry.id),
                            action: { Task { await install(entry) } }
                        )
                    }
                } header: {
                    HStack {
                        Text("Modules (\(filtered.count))")
                        Spacer()
                        if !languages.isEmpty {
                            Menu {
                                Button(L("All languages")) { languageFilter = nil }
                                ForEach(languages, id: \.self) { lang in
                                    Button(lang) { languageFilter = lang }
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "globe")
                                    Text(languageFilter ?? L("Language filter"))
                                }
                                .font(.caption)
                                .textCase(nil)
                            }
                        }
                    }
                }
            } else if !isLoading && errorMessage == nil {
                ContentUnavailableViewCompat(
                    title: L("No module"),
                    systemImage: "shippingbox",
                    description: L("No module found in this repository.")
                )
            }
        }
        .navigationTitle(ref?.displayName ?? repoURL)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: L("Search (name, author, type…)"))
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isBusy)
            }
        }
        .overlay {
            if isLoading {
                ProgressView(L("Scanning the repository…"))
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if bulkTotal > 0 {
                ProgressView(value: Double(bulkDone), total: Double(max(bulkTotal, 1))) {
                    Text(Lf("Installing %lld/%lld…", bulkDone, bulkTotal))
                }
                .frame(width: 220)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task { if entries.isEmpty { await load() } }
    }

    // MARK: - Actions

    private func load() async {
        guard let ref else {
            errorMessage = L("Unrecognized repository link.")
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await ModuleRepoScanner.scan(ref)
            entries = result.entries
            truncated = result.truncated
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func install(_ entry: RepoModuleEntry) async {
        busyIDs.insert(entry.id)
        let errors = await store.installFromRepo([entry]) { _ in }
        if let first = errors.first { errorMessage = first }
        busyIDs.remove(entry.id)
    }

    private func installAll(_ list: [RepoModuleEntry]) async {
        guard !list.isEmpty else { return }
        errorMessage = nil
        bulkDone = 0
        bulkTotal = list.count
        let errors = await store.installFromRepo(list) { done in bulkDone = done }
        bulkTotal = 0
        if !errors.isEmpty {
            errorMessage = Lf("%lld module(s) failed:", errors.count) + "\n" + errors.joined(separator: "\n")
        }
    }
}

/// Ligne d'un module trouvé dans un dépôt.
private struct RepoModuleRow: View {
    let entry: RepoModuleEntry
    /// Version installée (nil = pas installé).
    let installedVersion: String?
    let busy: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: entry.manifest.iconUrl, cornerRadius: 8)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.manifest.sourceName).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    Text("v\(entry.manifest.version)")
                    if let l = entry.manifest.language { Text("· \(l)") }
                    if let t = entry.manifest.type { Text("· \(t)") }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(entry.folder.isEmpty ? entry.path : "\(entry.folder)/")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if busy {
                ProgressView()
            } else if let installedVersion {
                if installedVersion == entry.manifest.version {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Button(L("Update"), action: action)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                        Text("v\(installedVersion) → v\(entry.manifest.version)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button(L("Add"), action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
