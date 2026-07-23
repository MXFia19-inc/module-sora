import Foundation

/// Un module par défaut proposé en ajout rapide (les 8 modules de MXFia19).
struct DefaultModule: Identifiable, Hashable {
    var name: String
    var manifestUrl: String
    var id: String { manifestUrl }
}

enum ModuleStoreError: LocalizedError {
    case badManifestURL
    case badScriptURL
    case network(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .badManifestURL: return "URL de manifest invalide."
        case .badScriptURL: return "URL de script (scriptUrl) invalide dans le manifest."
        case .network(let m): return "Erreur réseau : \(m)"
        case .decode(let m): return "Manifest illisible : \(m)"
        }
    }
}

/// Gère la liste des modules installés : persistance, ajout par URL, ajout rapide,
/// import de fichier local, rafraîchissement et suppression.
@MainActor
final class ModuleStore: ObservableObject {
    @Published private(set) var modules: [LoadedModule] = []

    private let fileURL: URL

    /// Les 8 modules connus de MXFia19 (ajout en un tap).
    static let defaults: [DefaultModule] = {
        let base = "https://raw.githubusercontent.com/MXFia19/module-sora/main"
        let folders = [
            "anime sama", "anime ultra", "hostcord", "movix",
            "nakios", "purstream", "voir anime", "wavewatch",
        ]
        return folders.map { folder in
            let enc = folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folder
            return DefaultModule(name: folder, manifestUrl: "\(base)/\(enc)/\(enc).json")
        }
    }()

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("modules.json")
        load()
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

    private func upsert(_ module: LoadedModule) {
        if let idx = modules.firstIndex(where: { $0.id == module.id }) {
            modules[idx] = module
        } else {
            modules.append(module)
        }
        persist()
    }

    func remove(_ module: LoadedModule) {
        modules.removeAll { $0.id == module.id }
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
