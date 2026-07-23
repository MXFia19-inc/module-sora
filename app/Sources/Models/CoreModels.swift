import Foundation

/// Élément de résultat de recherche (`searchResults`).
struct SearchItem: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var image: String
    var href: String
}

/// Détails d'un média (`extractDetails`, tableau à 1 élément).
struct MediaDetail: Hashable {
    var description: String
    var aliases: String
    var airdate: String

    static let empty = MediaDetail(description: "N/A", aliases: "N/A", airdate: "N/A")
}

/// Un épisode (`extractEpisodes`).
struct EpisodeLink: Identifiable, Hashable {
    let id = UUID()
    var href: String
    var number: Double
    var title: String?
    var image: String?
    var season: Int?

    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        let n = number.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(number)) : String(number)
        return "Épisode \(n)"
    }
}

/// Un flux jouable (`extractStreamUrl`).
struct StreamResult: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var url: String
    var headers: [String: String]

    var isHLS: Bool { url.lowercased().contains(".m3u8") }
}

/// Une piste de sous-titres.
struct SubtitleTrack: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var url: String
}

/// Résultat complet d'une extraction de flux.
struct StreamExtraction: Hashable {
    var streams: [StreamResult]
    var subtitles: [SubtitleTrack]

    var isEmpty: Bool { streams.isEmpty }
}
