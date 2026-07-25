import Foundation
import Combine

/// Réglages persistés de l'app (debug et lecture).
///
/// `@Published` + persistance `UserDefaults` manuelle (plutôt que `@AppStorage`,
/// qui ne publie pas de changement depuis une classe `ObservableObject`).
///
/// Non isolé au main : le moteur JS lit ces réglages depuis son thread dédié.
final class AppSettings: ObservableObject {
    @Published var jsTimeout: Double { didSet { defaults.set(jsTimeout, forKey: Keys.timeout) } }
    @Published var blockWebhooks: Bool { didSet { defaults.set(blockWebhooks, forKey: Keys.block) } }
    @Published var defaultUserAgent: String { didSet { defaults.set(defaultUserAgent, forKey: Keys.ua) } }

    // Mots-clés de recherche par type, utilisés par le testeur en masse.
    @Published var kwAnime: String { didSet { defaults.set(kwAnime, forKey: Keys.kwAnime) } }
    @Published var kwFilm: String { didSet { defaults.set(kwFilm, forKey: Keys.kwFilm) } }
    @Published var kwSerie: String { didSet { defaults.set(kwSerie, forKey: Keys.kwSerie) } }
    @Published var kwManga: String { didSet { defaults.set(kwManga, forKey: Keys.kwManga) } }

    /// Numéro d'épisode à tester pour les séries (étape Flux du testeur).
    @Published var serieEpisode: Int { didSet { defaults.set(serieEpisode, forKey: Keys.serieEp) } }

    /// Langue de l'interface (anglais par défaut).
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language); Loc.current = language }
    }

    /// Mot-clé libre par défaut pour la catégorie « Custom ».
    @Published var kwCustom: String { didSet { defaults.set(kwCustom, forKey: Keys.kwCustom) } }

    /// Vérifier chaque lien de flux retourné (serveur mort, en-têtes invalides…).
    @Published var checkStreams: Bool { didSet { defaults.set(checkStreams, forKey: Keys.checkStreams) } }

    /// Résoudre automatiquement les challenges Cloudflare dans un WebView.
    @Published var cloudflareBypass: Bool { didSet { defaults.set(cloudflareBypass, forKey: Keys.cloudflare) } }

    /// URL d'un webhook Discord pour recevoir le résumé du test en masse.
    @Published var discordWebhook: String { didSet { defaults.set(discordWebhook, forKey: Keys.webhook) } }

    /// Envoyer automatiquement le résumé à la fin d'un test en masse.
    @Published var autoSendReport: Bool { didSet { defaults.set(autoSendReport, forKey: Keys.autoSend) } }

    // MARK: - Surveillance planifiée

    @Published var monitorEnabled: Bool { didSet { defaults.set(monitorEnabled, forKey: Keys.monitorOn) } }
    /// Intervalle entre deux cycles, en heures (0.5 = 30 min).
    @Published var monitorHours: Double { didSet { defaults.set(monitorHours, forKey: Keys.monitorHours) } }
    /// Nom du préréglage surveillé (vide = tous les modules).
    @Published var monitorPresetName: String { didSet { defaults.set(monitorPresetName, forKey: Keys.monitorPreset) } }
    /// N'envoyer une notification qu'en cas de régression.
    @Published var monitorOnlyOnRegression: Bool { didSet { defaults.set(monitorOnlyOnRegression, forKey: Keys.monitorRegressionOnly) } }

    var monitorInterval: TimeInterval { max(0.5, monitorHours) * 3600 }

    static let monitorChoices: [Double] = [0.5, 1, 3, 6, 12, 24]

    var hasWebhook: Bool {
        !discordWebhook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func keyword(for category: TestCategory) -> String {
        switch category {
        case .anime: return kwAnime
        case .film: return kwFilm
        case .serie: return kwSerie
        case .manga: return kwManga
        case .custom: return kwCustom
        }
    }

    /// Motifs d'URL bloqués (un par ligne) quand le blocage des trackers est actif.
    /// Éditable pour suivre les changements de backend (Discord → Supabase → …).
    @Published var blockedPatternsText: String { didSet { defaults.set(blockedPatternsText, forKey: Keys.patterns) } }

    /// Motifs analysés depuis `blockedPatternsText`.
    var blockedURLPatterns: [String] {
        blockedPatternsText
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let timeout = "jsTimeout"
        static let block = "blockWebhooks"
        static let ua = "defaultUserAgent"
        static let patterns = "blockedPatterns"
        static let kwAnime = "kwAnime"
        static let kwFilm = "kwFilm"
        static let kwSerie = "kwSerie"
        static let kwManga = "kwManga"
        static let kwCustom = "kwCustom"
        static let checkStreams = "checkStreams"
        static let cloudflare = "cloudflareBypass"
        static let monitorOn = "monitorEnabled"
        static let monitorHours = "monitorHours"
        static let monitorPreset = "monitorPresetName"
        static let monitorRegressionOnly = "monitorOnlyOnRegression"
        static let webhook = "discordWebhook"
        static let autoSend = "autoSendReport"
        static let serieEp = "serieEpisode"
        static let language = "appLanguage"
        static let supabaseMigration = "migratedSupabase"
    }

    private static let defaultUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// Motifs bloqués par défaut : webhooks Discord + Supabase.
    private static let defaultPatterns = """
    discord.com/api/webhooks
    discordapp.com/api/webhooks
    supabase.co
    """

    init() {
        let d = UserDefaults.standard
        jsTimeout = d.object(forKey: Keys.timeout) as? Double ?? 30
        blockWebhooks = d.object(forKey: Keys.block) as? Bool ?? true
        defaultUserAgent = d.string(forKey: Keys.ua) ?? Self.defaultUA

        // Motifs bloqués + migration ponctuelle pour ajouter « supabase.co »
        // aux réglages déjà enregistrés (une seule fois : retirable ensuite).
        var patterns = d.string(forKey: Keys.patterns) ?? Self.defaultPatterns
        if !d.bool(forKey: Keys.supabaseMigration) {
            if !patterns.contains("supabase.co") {
                let trimmed = patterns.trimmingCharacters(in: .whitespacesAndNewlines)
                patterns = trimmed.isEmpty ? "supabase.co" : trimmed + "\nsupabase.co"
            }
            d.set(true, forKey: Keys.supabaseMigration)
            d.set(patterns, forKey: Keys.patterns)
        }
        blockedPatternsText = patterns
        kwAnime = d.string(forKey: Keys.kwAnime) ?? "one piece"
        kwFilm = d.string(forKey: Keys.kwFilm) ?? "interstellar"
        kwSerie = d.string(forKey: Keys.kwSerie) ?? "breaking bad"
        kwManga = d.string(forKey: Keys.kwManga) ?? "one piece"
        kwCustom = d.string(forKey: Keys.kwCustom) ?? ""
        checkStreams = d.object(forKey: Keys.checkStreams) as? Bool ?? false
        cloudflareBypass = d.object(forKey: Keys.cloudflare) as? Bool ?? true
        monitorEnabled = d.object(forKey: Keys.monitorOn) as? Bool ?? false
        monitorHours = d.object(forKey: Keys.monitorHours) as? Double ?? 6
        monitorPresetName = d.string(forKey: Keys.monitorPreset) ?? ""
        monitorOnlyOnRegression = d.object(forKey: Keys.monitorRegressionOnly) as? Bool ?? true
        discordWebhook = d.string(forKey: Keys.webhook) ?? ""
        autoSendReport = d.object(forKey: Keys.autoSend) as? Bool ?? false
        serieEpisode = d.object(forKey: Keys.serieEp) as? Int ?? 1
        let lang = AppLanguage(rawValue: d.string(forKey: Keys.language) ?? "en") ?? .en
        language = lang
        Loc.current = lang
    }
}
