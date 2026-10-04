import Foundation

/// Un module par défaut proposé en ajout rapide.
struct DefaultModule: Identifiable, Hashable {
    var name: String
    var manifestUrl: String
    var id: String { manifestUrl }
}

/// Une bibliothèque : un index JSON qui liste des modules à ajouter.
struct ModuleLibrarySource: Identifiable, Hashable {
    var name: String
    var url: String
    var id: String { url }
}

enum ModuleStoreError: LocalizedError {
    case badManifestURL
    case badScriptURL
    case network(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .badManifestURL: return L("Invalid manifest URL.")
        case .badScriptURL: return L("Invalid script URL (scriptUrl) in the manifest.")
        case .network(let m): return Lf("Network error: %@", m)
        case .decode(let m): return Lf("Unreadable manifest: %@", m)
        }
    }
}

/// Gère la liste des modules installés : persistance, ajout par URL, ajout rapide,
/// import de fichier local, rafraîchissement et suppression.
@MainActor
final class ModuleStore: ObservableObject {
    @Published private(set) var modules: [LoadedModule] = []
    /// Identifiants des modules épinglés (favoris).
    @Published private(set) var pinned: Set<String> = []

    /// Dépôts de modules enregistrés (liens GitHub / Gitea).
    @Published private(set) var repos: [String] = []

    private let fileURL: URL
    private let pinsKey = "pinnedModules"
    private let reposKey = "moduleRepos"

    /// Modules connus de MXFia19 sur la source Luna (ajout en un tap).
    /// Pattern : `…/raw/branch/main/<dossier>/<dossier>.json`.
    static let defaults: [DefaultModule] = {
        let base = "https://git.luna-app.eu/MXFia19/sources/raw/branch/main"
        let folders = [
            "aether", "anime-sama", "anime-ultra", "bingebox", "cinepulse",
            "dessin-anime", "livewatch", "miruro", "movix", "nakanime",
            "Nakastream", "nakios", "purstream", "scan-sama", "twitch-no-sub",
            "voir-anime",
        ]
        return folders.map { folder in
            DefaultModule(name: folder, manifestUrl: "\(base)/\(folder)/\(folder).json")
        }
    }()

    /// Bibliothèques proposées par défaut (index JSON de modules).
    static let defaultLibraries: [ModuleLibrarySource] = [
        ModuleLibrarySource(name: "Cufiy", url: "https://library.cufiy.net/api/modules.min.json"),
    ]

    /// Dépôts proposés au premier lancement.
    static let defaultRepos: [String] = ["https://github.com/MXFia19/module-sora"]

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("modules.json")
        load()
        pinned = Set(UserDefaults.standard.stringArray(forKey: pinsKey) ?? [])
        repos = UserDefaults.standard.stringArray(forKey: reposKey) ?? ModuleStore.defaultRepos
    }

    // MARK: - Dépôts

    /// Ajoute un dépôt. Renvoie `false` s'il était déjà enregistré.
    @discardableResult
    func addRepo(_ url: String) -> Bool {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !repos.contains(clean) else { return false }
        repos.append(clean)
        UserDefaults.standard.set(repos, forKey: reposKey)
        return true
    }

    func removeRepo(_ url: String) {
        repos.removeAll { $0 == url }
        UserDefaults.standard.set(repos, forKey: reposKey)
    }

    /// Module installé correspondant à une entrée de dépôt (même script ou même manifest).
    func installed(for entry: RepoModuleEntry) -> LoadedModule? {
        modules.first {
            $0.manifest.scriptUrl == entry.manifest.scriptUrl || $0.manifest.manifestUrl == entry.manifestURL
        }
    }

    /// Installe (ou met à jour) des modules trouvés dans un dépôt : le manifest est
    /// déjà lu, seul le script est téléchargé (6 à la fois). `progress` reçoit le
    /// nombre de modules traités. Renvoie les échecs, une ligne « nom : erreur » chacun.
    func installFromRepo(_ entries: [RepoModuleEntry], progress: @escaping (Int) -> Void) async -> [String] {
        var errors: [String] = []
        var done = 0
        let limit = 6
        await withTaskGroup(of: (RepoModuleEntry, Result<Data, Error>).self) { group in
            var next = 0
            while next < min(limit, entries.count) {
                let entry = entries[next]
                next += 1
                group.addTask {
                    let result = await ModuleStore.download(entry.manifest.scriptUrl)
                    return (entry, result)
                }
            }
            for await (entry, result) in group {
                switch result {
                case .success(let data):
                    var manifest = entry.manifest
                    manifest.manifestUrl = entry.manifestURL
                    // Le manifest a pu changer de scriptUrl : on remplace l'ancienne installation.
                    if let existing = installed(for: entry), existing.manifest.scriptUrl != manifest.scriptUrl {
                        modules.removeAll { $0.id == existing.id }
                    }
                    upsert(LoadedModule(manifest: manifest,
                                        scriptContent: String(decoding: data, as: UTF8.self),
                                        addedAt: Date()), save: false)
                case .failure(let error):
                    errors.append("\(entry.manifest.sourceName) : \(error.localizedDescription)")
                }
                done += 1
                progress(done)
                if next < entries.count {
                    let entry = entries[next]
                    next += 1
                    group.addTask {
                        let result = await ModuleStore.download(entry.manifest.scriptUrl)
                        return (entry, result)
                    }
                }
            }
        }
        persist()
        return errors
    }

    /// Téléchargement brut hors du main actor (scripts des modules d'un dépôt).
    nonisolated private static func download(_ urlString: String) async -> Result<Data, Error> {
        guard let url = URL(string: urlString) else { return .failure(ModuleStoreError.badScriptURL) }
        var request = URLRequest(url: url)
        request.setValue("ModuleTester/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failure(ModuleStoreError.network("HTTP \(http.statusCode) pour \(url.lastPathComponent)"))
            }
            return .success(data)
        } catch {
            return .failure(ModuleStoreError.network(error.localizedDescription))
        }
    }

    // MARK: - Favoris

    func isPinned(_ module: LoadedModule) -> Bool { pinned.contains(module.id) }

    func togglePin(_ module: LoadedModule) {
        if pinned.contains(module.id) { pinned.remove(module.id) } else { pinned.insert(module.id) }
        UserDefaults.standard.set(Array(pinned), forKey: pinsKey)
    }

    // MARK: - Persistance

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        modules = (try? JSONDecoder().decode([LoadedModule].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(modules) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Mutations

    private func upsert(_ module: LoadedModule, save: Bool = true) {
        if let idx = modules.firstIndex(where: { $0.id == module.id }) {
            modules[idx] = module
        } else {
            modules.append(module)
        }
        if save { persist() }
    }

    func remove(_ module: LoadedModule) {
        modules.removeAll { $0.id == module.id }
        persist()
    }

    func removeAll() {
        modules.removeAll()
        persist()
    }

    /// Ajoute (ou met à jour) un module à partir de l'URL de son manifest.
    @discardableResult
    func addByManifestURL(_ urlString: String) async throws -> LoadedModule {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ModuleStoreError.badManifestURL
        }
        let manifestData = try await fetchData(url)
        var manifest: ModuleManifest
        do {
            manifest = try JSONDecoder().decode(ModuleManifest.self, from: manifestData)
        } catch {
            throw ModuleStoreError.decode(error.localizedDescription)
        }
        manifest.manifestUrl = urlString

        guard let scriptURL = URL(string: manifest.scriptUrl) else {
            throw ModuleStoreError.badScriptURL
        }
        let scriptData = try await fetchData(scriptURL)
        let script = String(decoding: scriptData, as: UTF8.self)

        let module = LoadedModule(manifest: manifest, scriptContent: script, addedAt: Date())
        upsert(module)
        return module
    }

    /// Ajoute un module à partir d'un manifest déjà décodé (télécharge son script).
    /// Utilisé par les entrées de bibliothèque qui embarquent le manifest inline.
    @discardableResult
    func add(manifest: ModuleManifest) async throws -> LoadedModule {
        guard let scriptURL = URL(string: manifest.scriptUrl) else {
            throw ModuleStoreError.badScriptURL
        }
        let scriptData = try await fetchData(scriptURL)
        let module = LoadedModule(
            manifest: manifest,
            scriptContent: String(decoding: scriptData, as: UTF8.self),
            addedAt: Date()
        )
        upsert(module)
        return module
    }

    /// Télécharge des données brutes (partagé avec le chargeur de bibliothèque).
    func data(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ModuleStoreError.badManifestURL
        }
        return try await fetchData(url)
    }

    /// Re-télécharge le manifest et le script d'un module déjà installé.
    @discardableResult
    func refresh(_ module: LoadedModule) async throws -> LoadedModule {
        let source = module.manifest.manifestUrl ?? module.manifest.scriptUrl
        // Si on a l'URL du manifest, on refait tout ; sinon on ne rafraîchit que le script.
        if let manifestUrl = module.manifest.manifestUrl {
            return try await addByManifestURL(manifestUrl)
        }
        guard let scriptURL = URL(string: source) else { throw ModuleStoreError.badScriptURL }
        let scriptData = try await fetchData(scriptURL)
        var updated = module
        updated.scriptContent = String(decoding: scriptData, as: UTF8.self)
        updated.addedAt = Date()
        upsert(updated)
        return updated
    }

    /// Importe un module depuis des données locales (manifest JSON + script JS).
    @discardableResult
    func addLocal(manifestData: Data, scriptData: Data) throws -> LoadedModule {
        var manifest: ModuleManifest
        do {
            manifest = try JSONDecoder().decode(ModuleManifest.self, from: manifestData)
        } catch {
            throw ModuleStoreError.decode(error.localizedDescription)
        }
        let module = LoadedModule(
            manifest: manifest,
            scriptContent: String(decoding: scriptData, as: UTF8.self),
            addedAt: Date()
        )
        upsert(module)
        return module
    }

    /// Crée (ou écrase) un module à partir de code JS collé.
    /// Si `overwriting` est fourni, remplace son script en conservant son identité
    /// (utile pour tester une version locale d'un module déjà installé).
    @discardableResult
    func addPasted(name: String, type: String?, language: String?, script: String,
                   overwriting existing: LoadedModule?) -> LoadedModule {
        let module: LoadedModule
        if let existing {
            var updated = existing
            updated.scriptContent = script
            updated.addedAt = Date()
            module = updated
        } else {
            let manifest = ModuleManifest(
                sourceName: name.isEmpty ? "Module local" : name,
                scriptUrl: "local://\(UUID().uuidString)",
                type: (type?.isEmpty == false) ? type : nil,
                language: (language?.isEmpty == false) ? language : nil
            )
            module = LoadedModule(manifest: manifest, scriptContent: script, addedAt: Date())
        }
        upsert(module)
        return module
    }

    // MARK: - Réseau

    private func fetchData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("ModuleTester/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw ModuleStoreError.network("HTTP \(http.statusCode) pour \(url.lastPathComponent)")
            }
            return data
        } catch let e as ModuleStoreError {
            throw e
        } catch {
            throw ModuleStoreError.network(error.localizedDescription)
        }
    }
}
