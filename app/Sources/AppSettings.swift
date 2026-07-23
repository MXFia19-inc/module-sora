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

    func keyword(for category: TestCategory) -> String {
        switch category {
        case .anime: return kwAnime
        case .film: return kwFilm
        case .serie: return kwSerie
        case .manga: return kwManga
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
        static let serieEp = "serieEpisode"
    }

    private static let defaultUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// Motifs par défaut : anciens webhooks Discord (sans risque).
    /// Pour le tracking Supabase, ajoute dans les Réglages l'endpoint EXACT
    /// (ex. `<projet>.supabase.co/rest/v1/<table_de_tracking>`) — ne bloque pas
    /// tout Supabase, au cas où un module y lise aussi ses données.
    private static let defaultPatterns = """
    discord.com/api/webhooks
    discordapp.com/api/webhooks
    """

    init() {
        let d = UserDefaults.standard
        jsTimeout = d.object(forKey: Keys.timeout) as? Double ?? 30
        blockWebhooks = d.object(forKey: Keys.block) as? Bool ?? true
        defaultUserAgent = d.string(forKey: Keys.ua) ?? Self.defaultUA
        blockedPatternsText = d.string(forKey: Keys.patterns) ?? Self.defaultPatterns
        kwAnime = d.string(forKey: Keys.kwAnime) ?? "one piece"
        kwFilm = d.string(forKey: Keys.kwFilm) ?? "interstellar"
        kwSerie = d.string(forKey: Keys.kwSerie) ?? "breaking bad"
        kwManga = d.string(forKey: Keys.kwManga) ?? "one piece"
        serieEpisode = d.object(forKey: Keys.serieEp) as? Int ?? 1
    }
}
