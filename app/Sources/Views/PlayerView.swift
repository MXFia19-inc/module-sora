import SwiftUI
import UIKit
import AVKit
import AVFoundation

/// Lecteur natif : AVPlayer avec en-têtes HTTP par flux + export vers apps tierces.
struct PlayerView: View {
    let stream: StreamResult
    let subtitles: [SubtitleTrack]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AVPlayerContainer(stream: stream)
                .ignoresSafeArea()

            HStack(spacing: 16) {
                Menu {
                    ForEach(ExternalPlayer.allCases) { player in
                        if let url = player.url(for: stream.url) {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                Label("Ouvrir dans \(player.name)", systemImage: "arrow.up.forward.app")
                            }
                        }
                    }
                    Button {
                        UIPasteboard.general.string = stream.url
                    } label: { Label("Copier l'URL du flux", systemImage: "doc.on.doc") }
                } label: {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if !subtitles.isEmpty {
                Text("\(subtitles.count) piste(s) de sous-titres — non muxées par le lecteur natif ; utilisez l'export.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }
}

/// Enveloppe AVPlayerViewController avec en-têtes HTTP personnalisés.
private struct AVPlayerContainer: UIViewControllerRepresentable {
    let stream: StreamResult

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let controller0 = AVPlayerViewController()
        guard let url = URL(string: stream.url) else { return controller0 }

        var options: [String: Any] = [:]
        if !stream.headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = stream.headers
        }
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true

        let controller = controller0
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}

/// Lecteurs tiers cibles pour l'export.
private enum ExternalPlayer: String, CaseIterable, Identifiable {
    case vlc, infuse, outplayer
    var id: String { rawValue }

    var name: String {
        switch self {
        case .vlc: return "VLC"
        case .infuse: return "Infuse"
        case .outplayer: return "Outplayer"
        }
    }

    func url(for streamURL: String) -> URL? {
        guard let encoded = streamURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        switch self {
        case .vlc:
            return URL(string: "vlc://\(streamURL)")
        case .infuse:
            return URL(string: "infuse://x-callback-url/play?url=\(encoded)")
        case .outplayer:
            return URL(string: "outplayer://\(streamURL)")
        }
    }
}
