import Foundation

/// Un module installé dans l'app : son manifest + le script JS mis en cache.
struct LoadedModule: Codable, Identifiable, Hashable {
    var manifest: ModuleManifest
    var scriptContent: String
    var addedAt: Date

    var id: String { manifest.id }
    var name: String { manifest.sourceName }
}
