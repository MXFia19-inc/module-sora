import Foundation

/// Un préréglage de test en masse : une sélection de modules avec leurs
/// catégories forcées et leurs mots-clés personnalisés.
struct TestPreset: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Identifiants des modules sélectionnés.
    var moduleIds: [String]
    /// Catégorie forcée par module (valeur brute de `TestCategory`).
    var overrides: [String: String]
    /// Mot-clé libre par module.
    var customKeywords: [String: String]
    var createdAt: Date = Date()
}
