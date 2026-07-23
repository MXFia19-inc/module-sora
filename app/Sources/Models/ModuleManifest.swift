import Foundation

/// Auteur d'un module (objet `author` du manifest).
struct ModuleAuthor: Codable, Hashable {
    var name: String
    var icon: String?
    var url: String?
}

/// Manifest d'un module « Sora ».
///
/// Décodage tolérant : accepte à la fois la casse standard (`iconUrl`, `scriptUrl`)
/// et les variantes façon Luna (`iconURL`, `scriptURL`).
struct ModuleManifest: Codable, Identifiable, Hashable {
    var sourceName: String
    var iconUrl: String?
    var author: ModuleAuthor?
    var version: String
    var language: String?
    var streamType: String?
    var quality: String?
    var baseUrl: String?
    var searchBaseUrl: String?
    var scriptUrl: String
    var type: String?
    var downloadSupport: Bool?
    var asyncJS: Bool?
    var softsub: Bool?

    /// URL du .json d'origine (renseignée côté app lors de l'ajout par URL).
    var manifestUrl: String?

    /// Identité stable : dérivée du scriptUrl.
    var id: String { scriptUrl }

    // MARK: - Décodage tolérant

    private enum CodingKeys: String, CodingKey {
        case sourceName, iconUrl, author, version, language, streamType, quality
        case baseUrl, searchBaseUrl, scriptUrl, type, downloadSupport, asyncJS, softsub
        case manifestUrl
    }

    private enum LunaKeys: String, CodingKey {
        case iconURL, scriptURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let luna = try? decoder.container(keyedBy: LunaKeys.self)

        sourceName = try c.decode(String.self, forKey: .sourceName)
        version = (try? c.decode(String.self, forKey: .version)) ?? "1.0.0"
        author = try? c.decode(ModuleAuthor.self, forKey: .author)
        language = try? c.decode(String.self, forKey: .language)
        streamType = try? c.decode(String.self, forKey: .streamType)
        quality = try? c.decode(String.self, forKey: .quality)
        baseUrl = try? c.decode(String.self, forKey: .baseUrl)
        searchBaseUrl = try? c.decode(String.self, forKey: .searchBaseUrl)
        type = try? c.decode(String.self, forKey: .type)
        downloadSupport = try? c.decode(Bool.self, forKey: .downloadSupport)
        asyncJS = try? c.decode(Bool.self, forKey: .asyncJS)
        softsub = try? c.decode(Bool.self, forKey: .softsub)
        manifestUrl = try? c.decode(String.self, forKey: .manifestUrl)

        iconUrl = (try? c.decode(String.self, forKey: .iconUrl))
            ?? (try? luna?.decode(String.self, forKey: .iconURL))

        if let s = try? c.decode(String.self, forKey: .scriptUrl) {
            scriptUrl = s
        } else if let s = try? luna?.decode(String.self, forKey: .scriptURL) {
            scriptUrl = s
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.scriptUrl,
                .init(codingPath: decoder.codingPath, debugDescription: "scriptUrl/scriptURL manquant")
            )
        }
    }
}
