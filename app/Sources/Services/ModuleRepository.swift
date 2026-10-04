import Foundation

/// Hébergeur d'un dépôt de modules.
enum RepoHostKind: String {
    case github
    /// Gitea / Forgejo (Codeberg, git.luna-app.eu…) : même API `/api/v1`.
    case gitea
}

/// Un dépôt de modules désigné par son lien (`https://github.com/owner/repo`,
/// `…/tree/<branche>/<dossier>`, `owner/repo`, ou l'équivalent Gitea
/// `…/src/branch/<branche>/<dossier>`).
struct ModuleRepoRef: Hashable {
    var kind: RepoHostKind
    var host: String
    var owner: String
    var repo: String
    /// Branche demandée dans le lien ; `nil` = branche par défaut du dépôt.
    var branch: String?
    /// Dossier auquel limiter l'analyse ("" = tout le dépôt).
    var subpath: String

    var displayName: String {
        subpath.isEmpty ? "\(owner)/\(repo)" : "\(owner)/\(repo)/\(subpath)"
    }

    static func parse(_ input: String) -> ModuleRepoRef? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.lowercased().hasSuffix(".git") { s.removeLast(4) }
        guard !s.isEmpty else { return nil }

        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            // Raccourci « owner/repo » = GitHub.
            let parts = s.split(separator: "/").map(String.init)
            if parts.count == 2, !parts[0].contains(".") {
                return ModuleRepoRef(kind: .github, host: "github.com", owner: parts[0],
                                     repo: parts[1], branch: nil, subpath: "")
            }
            s = "https://" + s
        }

        guard let url = URL(string: s), let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }

        var branch: String?
        var subpath = ""
        if parts.count >= 4, parts[2] == "tree" {
            // GitHub : /owner/repo/tree/<branche>/<dossier…>
            branch = parts[3]
            subpath = parts.dropFirst(4).joined(separator: "/")
        } else if parts.count >= 5, parts[2] == "src", parts[3] == "branch" {
            // Gitea : /owner/repo/src/branch/<branche>/<dossier…>
            branch = parts[4]
            subpath = parts.dropFirst(5).joined(separator: "/")
        }

        let kind: RepoHostKind = (host == "github.com" || host == "www.github.com") ? .github : .gitea
        return ModuleRepoRef(kind: kind, host: kind == .github ? "github.com" : host,
                             owner: parts[0], repo: parts[1], branch: branch, subpath: subpath)
    }
}

/// Un module trouvé dans un dépôt : son manifest et l'URL brute de ce manifest.
struct RepoModuleEntry: Identifiable, Hashable {
    /// Chemin du manifest dans le dépôt (ex. `movix/movix.json`).
    let path: String
    /// URL brute du manifest (sert aussi au rafraîchissement du module installé).
    let manifestURL: String
    let manifest: ModuleManifest

    var id: String { path }

    /// Dossier du manifest ("" à la racine).
    var folder: String { ModuleRepoScanner.directory(of: path) }
}

struct RepoScanResult {
    var entries: [RepoModuleEntry]
    /// L'hébergeur a tronqué la liste des fichiers : des modules peuvent manquer.
    var truncated: Bool
}

enum ModuleRepoError: LocalizedError {
    case invalidLink
    case notFound
    case rateLimited
    case http(Int, String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidLink: return L("Unrecognized repository link.")
        case .notFound: return L("Repository or branch not found.")
        case .rateLimited:
            return L("GitHub API rate limit reached (60 requests per hour without an account). Try again later.")
        case .http(let code, let what): return Lf("HTTP %lld for %@", code, what)
        case .network(let m): return Lf("Network error: %@", m)
        }
    }
}

/// Trouve tous les modules d'un dépôt.
///
/// Une seule requête d'API liste l'arborescence complète (GitHub :
/// `git/trees/<ref>?recursive=1`, Gitea : `api/v1/…/git/trees`). Est candidat
/// tout `.json` posé dans un dossier qui contient aussi un `.js` (hors fichiers
/// d'outillage comme `package.json`) ; il est retenu s'il se décode comme un
/// manifest (`sourceName` + `scriptUrl`). Les manifests sont lus sur les URLs
/// brutes, qui ne comptent pas dans le quota de l'API GitHub.
enum ModuleRepoScanner {
    static let excludedNames: Set<String> = [
        "package.json", "package-lock.json", "tsconfig.json", "jsconfig.json",
        "composer.json", "bower.json", ".eslintrc.json", "vercel.json",
    ]

    /// Téléchargements de manifests simultanés.
    private static let concurrency = 8

    static func scan(_ ref: ModuleRepoRef) async throws -> RepoScanResult {
        let listing = try await listFiles(ref)
        let paths = candidates(in: listing.files, subpath: ref.subpath)
        let items = paths.map { (path: $0, url: listing.rawBase + encodePath($0)) }
        let entries = await fetchManifests(items)
        let sorted = entries.sorted {
            $0.manifest.sourceName.localizedCaseInsensitiveCompare($1.manifest.sourceName) == .orderedAscending
        }
        return RepoScanResult(entries: sorted, truncated: listing.truncated)
    }

    // MARK: - Arborescence

    private struct TreeResponse: Decodable {
        struct Item: Decodable {
            let path: String
            let type: String
        }
        let tree: [Item]?
        let truncated: Bool?
    }

    private struct GiteaRepoInfo: Decodable {
        let defaultBranch: String
        enum CodingKeys: String, CodingKey { case defaultBranch = "default_branch" }
    }

    private struct Listing {
        var files: [String]
        var truncated: Bool
        /// Préfixe des URLs brutes, terminé par "/".
        var rawBase: String
    }

    private static func listFiles(_ ref: ModuleRepoRef) async throws -> Listing {
        let owner = encodePath(ref.owner), repo = encodePath(ref.repo)
        switch ref.kind {
        case .github:
            // "HEAD" = branche par défaut, sans requête supplémentaire.
            let tree = encodePath(ref.branch ?? "HEAD")
            let data = try await get("https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(tree)?recursive=1")
            let response = try decodeTree(data)
            let files = (response.tree ?? []).filter { $0.type == "blob" }.map { $0.path }
            return Listing(files: files, truncated: response.truncated == true,
                           rawBase: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(tree)/")

        case .gitea:
            let api = "https://\(ref.host)/api/v1/repos/\(owner)/\(repo)"
            var branch = ref.branch ?? ""
            if branch.isEmpty {
                let info = try await get(api)
                guard let decoded = try? JSONDecoder().decode(GiteaRepoInfo.self, from: info) else {
                    throw ModuleRepoError.notFound
                }
                branch = decoded.defaultBranch
            }
            let encodedBranch = encodePath(branch)
            var files: [String] = []
            var truncated = false
            var page = 1
            while true {
                let data = try await get("\(api)/git/trees/\(encodedBranch)?recursive=true&per_page=1000&page=\(page)")
                let response = try decodeTree(data)
                let items = response.tree ?? []
                files += items.filter { $0.type == "blob" }.map { $0.path }
                if response.truncated != true || items.isEmpty { break }
                page += 1
                if page > 20 { truncated = true; break }
            }
            return Listing(files: files, truncated: truncated,
                           rawBase: "https://\(ref.host)/\(owner)/\(repo)/raw/branch/\(encodedBranch)/")
        }
    }

    private static func decodeTree(_ data: Data) throws -> TreeResponse {
        do {
            return try JSONDecoder().decode(TreeResponse.self, from: data)
        } catch {
            throw ModuleRepoError.network(error.localizedDescription)
        }
    }

    /// Manifests candidats : `.json` dans un dossier qui contient aussi un `.js`.
    static func candidates(in files: [String], subpath: String) -> [String] {
        let scoped = files.filter { subpath.isEmpty || $0 == subpath || $0.hasPrefix(subpath + "/") }
        let jsDirs = Set(scoped.filter { $0.lowercased().hasSuffix(".js") }.map { directory(of: $0) })
        return scoped.filter { path in
            let name = (path.split(separator: "/").last.map(String.init) ?? path).lowercased()
            guard name.hasSuffix(".json"), !excludedNames.contains(name) else { return false }
            if path.hasPrefix("node_modules/") || path.contains("/node_modules/") || path.hasPrefix(".github/") {
                return false
            }
            return jsDirs.contains(directory(of: path))
        }
    }

    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    // MARK: - Manifests

    private static func fetchManifests(_ items: [(path: String, url: String)]) async -> [RepoModuleEntry] {
        var entries: [RepoModuleEntry] = []
        await withTaskGroup(of: RepoModuleEntry?.self) { group in
            var next = 0
            while next < min(concurrency, items.count) {
                let item = items[next]
                next += 1
                group.addTask { await ModuleRepoScanner.manifest(path: item.path, url: item.url) }
            }
            for await entry in group {
                if let entry { entries.append(entry) }
                if next < items.count {
                    let item = items[next]
                    next += 1
                    group.addTask { await ModuleRepoScanner.manifest(path: item.path, url: item.url) }
                }
            }
        }
        return entries
    }

    private static func manifest(path: String, url: String) async -> RepoModuleEntry? {
        guard var data = try? await get(url) else { return nil }
        // BOM UTF-8 éventuel (fichiers enregistrés par PowerShell).
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        guard var manifest = try? JSONDecoder().decode(ModuleManifest.self, from: Data(data)) else { return nil }
        // scriptUrl relatif : on le résout par rapport au manifest.
        if !manifest.scriptUrl.contains("://"),
           let resolved = URL(string: manifest.scriptUrl, relativeTo: URL(string: url))?.absoluteURL {
            manifest.scriptUrl = resolved.absoluteString
        }
        return RepoModuleEntry(path: path, manifestURL: url, manifest: manifest)
    }

    // MARK: - Réseau

    static func encodePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    private static func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw ModuleRepoError.invalidLink }
        var request = URLRequest(url: url)
        request.setValue("ModuleTester/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw ModuleRepoError.network(error.localizedDescription)
        }
        let (data, response) = result
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if url.host == "api.github.com", http.statusCode == 403 || http.statusCode == 429 {
                throw ModuleRepoError.rateLimited
            }
            if http.statusCode == 404 { throw ModuleRepoError.notFound }
            throw ModuleRepoError.http(http.statusCode, url.lastPathComponent)
        }
        return data
    }
}
