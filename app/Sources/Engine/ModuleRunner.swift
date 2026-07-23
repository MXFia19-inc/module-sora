import Foundation

/// Résultat typé d'un appel de module, accompagné de la chaîne JSON brute
/// (pour l'affichage « voir le JSON brut »).
struct RunResult<T> {
    let value: T
    let raw: String
}

/// Pilote un module : charge son script dans un `JSEngine` puis appelle les
/// quatre fonctions du contrat et parse leurs sorties (parsing tolérant).
@MainActor
final class ModuleRunner {
    let module: LoadedModule
    private let engine: JSEngine

    init(module: LoadedModule, debugLog: DebugLog, settings: AppSettings) throws {
        self.module = module
        self.engine = try JSEngine(moduleName: module.name, debugLog: debugLog, settings: settings)
        try engine.evaluate(script: module.scriptContent)
    }

    // MARK: - Fonctions du contrat

    func search(_ keyword: String) async throws -> RunResult<[SearchItem]> {
        let raw = try await engine.callAsync("searchResults", [keyword])
        return RunResult(value: Self.parseSearch(raw), raw: raw)
    }

    func details(_ url: String) async throws -> RunResult<MediaDetail> {
        let raw = try await engine.callAsync("extractDetails", [url])
        return RunResult(value: Self.parseDetails(raw), raw: raw)
    }

    func episodes(_ url: String) async throws -> RunResult<[EpisodeLink]> {
        let raw = try await engine.callAsync("extractEpisodes", [url])
        return RunResult(value: Self.parseEpisodes(raw), raw: raw)
    }

    func streams(_ url: String) async throws -> RunResult<StreamExtraction> {
        let raw = try await engine.callAsync("extractStreamUrl", [url])
        return RunResult(value: Self.parseStreams(raw), raw: raw)
    }

    // MARK: - Parsing

    private static func jsonArray(_ raw: String) -> [Any] {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let arr = obj as? [Any] { return arr }
        if let dict = obj as? [String: Any] { return [dict] }
        return []
    }

    private static func str(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func toDouble(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    static func parseSearch(_ raw: String) -> [SearchItem] {
        jsonArray(raw).compactMap { item in
            guard let d = item as? [String: Any],
                  let title = str(d["title"]), let href = str(d["href"]) else { return nil }
            let image = str(d["image"]) ?? str(d["imageUrl"]) ?? str(d["poster"]) ?? ""
            return SearchItem(title: title, image: image, href: href)
        }
    }

    static func parseDetails(_ raw: String) -> MediaDetail {
        guard let first = jsonArray(raw).first as? [String: Any] else { return .empty }
        return MediaDetail(
            description: str(first["description"]) ?? "N/A",
            aliases: str(first["aliases"]) ?? "N/A",
            airdate: str(first["airdate"]) ?? "N/A"
        )
    }

    static func parseEpisodes(_ raw: String) -> [EpisodeLink] {
        jsonArray(raw).compactMap { item in
            guard let d = item as? [String: Any], let href = str(d["href"]) else { return nil }
            return EpisodeLink(
                href: href,
                number: toDouble(d["number"]) ?? 0,
                title: str(d["title"]),
                image: str(d["image"]) ?? str(d["imageUrl"]),
                season: (d["season"] as? Int) ?? Int(toDouble(d["season"]) ?? 0).nonZero
            )
        }
    }

    /// Parseur de flux tolérant (formes multiples héritées de Sora).
    static func parseStreams(_ raw: String) -> StreamExtraction {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var streams: [StreamResult] = []
        var subtitles: [SubtitleTrack] = []
        var seen = Set<String>()

        func addStream(_ title: String, _ url: String, _ headers: [String: String]) {
            let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !u.isEmpty, seen.insert(u).inserted else { return }
            streams.append(StreamResult(title: title.isEmpty ? "Lecture" : title, url: u, headers: headers))
        }

        // Cas 1 : URL brute (ni objet, ni tableau JSON).
        if !trimmed.hasPrefix("{"), !trimmed.hasPrefix("[") {
            if let url = URL(string: trimmed), url.scheme != nil {
                addStream("Lecture", trimmed, [:])
            }
            return StreamExtraction(streams: streams, subtitles: subtitles)
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return StreamExtraction(streams: streams, subtitles: subtitles)
        }

        // Tableau au premier niveau => liste de flux.
        if let arr = json as? [Any] {
            parseStreamArray(arr, [:], add: addStream)
            return StreamExtraction(streams: streams, subtitles: subtitles)
        }

        guard let obj = json as? [String: Any] else {
            return StreamExtraction(streams: streams, subtitles: subtitles)
        }

        let topHeaders = headersDict(obj["headers"])

        if let arr = obj["streams"] as? [Any] {
            parseStreamArray(arr, topHeaders, add: addStream)
        }
        if let s = str(obj["stream"]) {
            addStream("Stream", s, topHeaders)
        } else if let s = obj["stream"] as? [String: Any] {
            let url = str(s["url"]) ?? str(s["streamUrl"]) ?? str(s["file"]) ?? ""
            addStream(str(s["title"]) ?? "Stream", url, headersDict(s["headers"], fallback: topHeaders))
        }
        if streams.isEmpty, let s = str(obj["url"]) {
            addStream("Lecture", s, topHeaders)
        }

        parseSubtitles(obj, into: &subtitles)
        return StreamExtraction(streams: streams, subtitles: subtitles)
    }

    private static func parseStreamArray(
        _ arr: [Any], _ defaultHeaders: [String: String],
        add: (String, String, [String: String]) -> Void
    ) {
        for (i, item) in arr.enumerated() {
            if let s = item as? String {
                add("Flux \(i + 1)", s, defaultHeaders)
            } else if let d = item as? [String: Any] {
                let url = str(d["streamUrl"]) ?? str(d["url"]) ?? str(d["file"]) ?? str(d["src"]) ?? ""
                let title = str(d["title"]) ?? str(d["name"]) ?? str(d["label"]) ?? str(d["quality"]) ?? "Flux \(i + 1)"
                add(title, url, headersDict(d["headers"], fallback: defaultHeaders))
            }
        }
    }

    private static func parseSubtitles(_ obj: [String: Any], into subs: inout [SubtitleTrack]) {
        func addSub(_ url: String?, _ label: String?) {
            guard let url, !url.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            subs.append(SubtitleTrack(label: label?.isEmpty == false ? label! : "Sous-titres", url: url))
        }
        for key in ["subtitles", "subtitle"] {
            if let s = obj[key] as? String { addSub(s, "Sous-titres") }
        }
        for key in ["subtitles", "allSubtitles", "subtitle"] {
            guard let arr = obj[key] as? [Any] else { continue }
            for item in arr {
                if let s = item as? String { addSub(s, "Sous-titres") }
                else if let d = item as? [String: Any] {
                    let url = str(d["url"]) ?? str(d["file"]) ?? str(d["src"])
                    let label = str(d["label"]) ?? str(d["lang"]) ?? str(d["language"]) ?? str(d["name"]) ?? str(d["title"])
                    addSub(url, label)
                }
            }
        }
    }

    private static func headersDict(_ any: Any?, fallback: [String: String] = [:]) -> [String: String] {
        guard let d = any as? [String: Any] else { return fallback }
        var out: [String: String] = [:]
        for (k, v) in d { out[k] = "\(v)" }
        return out.isEmpty ? fallback : out
    }
}

private extension Int {
    /// nil si zéro (utilisé pour `season` optionnel).
    var nonZero: Int? { self == 0 ? nil : self }
}
