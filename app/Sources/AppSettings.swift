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

    /// Motifs d'URL bloqués quand `blockWebhooks` est actif (trackers Discord).
    let blockedURLPatterns = ["discord.com/api/webhooks", "discordapp.com/api/webhooks"]

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let timeout = "jsTimeout"
        static let block = "blockWebhooks"
        static let ua = "defaultUserAgent"
    }

    private static let defaultUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    init() {
        let d = UserDefaults.standard
        jsTimeout = d.object(forKey: Keys.timeout) as? Double ?? 30
        blockWebhooks = d.object(forKey: Keys.block) as? Bool ?? true
        defaultUserAgent = d.string(forKey: Keys.ua) ?? Self.defaultUA
    }
}
