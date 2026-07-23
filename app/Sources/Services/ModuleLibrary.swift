import Foundation

/// Une entrée listée par une bibliothèque (index JSON de modules).
struct LibraryModuleEntry: Identifiable {
    let id = UUID()
    var name: String
    var icon: String? = nil
    var version: String? = nil
    var author: String? = nil
    var type: String? = nil
    /// URL d'un manifest `.json` à télécharger (cas « liste d'URLs »).
    var manifestURL: String? = nil
    /// Manifest embarqué directement dans l'entrée (cas « liste de manifests »).
    var inlineManifest: ModuleManifest? = nil

    /// Clé stable pour repérer si le module est déjà installé.
    var installKey: String { inlineManifest?.scriptUrl ?? manifestURL ?? name }
}

/// Charge et parse un index de bibliothèque de modules (format tolérant :
/// Sora/Luna/cufiy renvoient soit un tableau de manifests, soit un tableau
/// d'objets pointant vers des URLs de manifests, éventuellement enveloppés).
enum ModuleLibrary {
    static func parse(_ data: Data) throws -> [LibraryModuleEntry] {
        let root = try JSONSerialization.jsonObject(with: data)

        var array: [Any] = []
        if let a = root as? [Any] {
            array = a
        } else if let d = root as? [String: Any] {
            for key in ["modules", "sources", "data", "items", "list", "results"] {
                if let a = d[key] as? [Any] { array = a; break }
            }
            // Repli : objet indexé par id de module (dictionnaire de manifests).
            if array.isEmpty {
                array = d.values.filter { $0 is [String: Any] }
            }
        }

        return array.compactMap { item -> LibraryModuleEntry? in
            guard let d = item as? [String: Any] else {
                // Entrée = simple URL de manifest en chaîne.
                if let url = item as? String, url.hasSuffix(".json") || url.contains("://") {
                    return LibraryModuleEntry(name: lastComponent(url), manifestURL: url)
                }
                return nil
            }

            let name = str(d["sourceName"]) ?? str(d["name"]) ?? str(d["title"]) ?? "Module"
            let icon = str(d["iconUrl"]) ?? str(d["iconURL"]) ?? str(d["icon"]) ?? str(d["image"])
            let version = str(d["version"])
            let author = str(d["author"]) ?? ((d["author"] as? [String: Any]).flatMap { str($0["name"]) })
            let type = str(d["type"])

            // Cas 1 : le manifest est embarqué (présence d'un scriptUrl/scriptURL).
            if d["scriptUrl"] != nil || d["scriptURL"] != nil,
               let raw = try? JSONSerialization.data(withJSONObject: d),
               let manifest = try? JSONDecoder().decode(ModuleManifest.self, from: raw) {
                return LibraryModuleEntry(name: name, icon: icon, version: version,
                                          author: author, type: type, inlineManifest: manifest)
            }

            // Cas 2 : l'entrée pointe vers une URL de manifest.
            let manifestURL = str(d["url"]) ?? str(d["manifestUrl"]) ?? str(d["manifest"])
                ?? str(d["module"]) ?? str(d["moduleURL"]) ?? str(d["json"]) ?? str(d["metadata"])
            guard let manifestURL, manifestURL.contains("://") else { return nil }
            return LibraryModuleEntry(name: name, icon: icon, version: version,
                                      author: author, type: type, manifestURL: manifestURL)
        }
    }

    private static func str(_ any: Any?) -> String? {
        if let s = any as? String, !s.isEmpty { return s }
        return nil
    }

    private static func lastComponent(_ url: String) -> String {
        url.split(separator: "/").last.map(String.init) ?? url
    }
}
