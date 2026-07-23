import SwiftUI

/// Image distante avec placeholder (iOS 16 : AsyncImage).
///
/// L'image ne dicte JAMAIS la taille de la vue : elle est dessinée en overlay
/// d'un `Color.clear` flexible, remplie puis rognée. Ainsi une image trop grande
/// renvoyée par un module ne déborde pas hors de l'écran — elle est simplement
/// contrainte au cadre imposé par l'appelant (frame / aspectRatio).
struct RemoteImage: View {
    let url: String?
    var cornerRadius: CGFloat = 6

    var body: some View {
        Color.gray.opacity(0.15)
            .overlay {
                AsyncImage(url: url.flatMap { URL(string: $0) }) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Équivalent minimal de `ContentUnavailableView` (iOS 17) pour iOS 16.
struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowSeparator(.hidden)
    }
}

/// Bannière d'erreur inline.
struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.callout)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}
