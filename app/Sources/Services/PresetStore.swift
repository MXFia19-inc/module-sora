import Foundation

/// Persistance des préréglages de test en masse (Documents/presets.json).
@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [TestPreset] = []

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("presets.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        presets = (try? JSONDecoder().decode([TestPreset].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Enregistre (ou écrase, si le nom existe déjà) un préréglage.
    @discardableResult
    func save(name: String,
              moduleIds: Set<String>,
              overrides: [String: TestCategory],
              customKeywords: [String: String]) -> TestPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ne garde que les mots-clés non vides.
        let keywords = customKeywords.filter {
            !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }
        var preset = TestPreset(
            name: trimmed.isEmpty ? "Preset" : trimmed,
            moduleIds: Array(moduleIds),
            overrides: overrides.mapValues { $0.rawValue },
            customKeywords: keywords
        )
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) {
            preset.id = presets[index].id
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
        return preset
    }

    func remove(_ preset: TestPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    /// Reconstruit les catégories forcées d'un préréglage.
    func categories(of preset: TestPreset) -> [String: TestCategory] {
        preset.overrides.compactMapValues { TestCategory(rawValue: $0) }
    }
}
