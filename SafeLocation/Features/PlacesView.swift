import SwiftUI

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofController
    @Environment(\.dismiss) private var dismiss
    let onSelect: (SavedPlace) -> Void

    var body: some View {
        NavigationStack {
            List {
                if !session.favorites.isEmpty {
                    Section("收藏") {
                        ForEach(session.favorites) { place in
                            placeRow(place, favorite: true)
                        }
                        .onDelete { offsets in
                            for index in offsets { session.removeFavorite(session.favorites[index]) }
                        }
                    }
                }

                if !session.recents.isEmpty {
                    Section("最近使用") {
                        ForEach(session.recents) { place in
                            placeRow(place, favorite: false)
                        }
                    }
                }

                if session.favorites.isEmpty && session.recents.isEmpty {
                    ContentUnavailableView("还没有位置", systemImage: "mappin.slash")
                }
            }
            .navigationTitle("位置")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !session.recents.isEmpty { Button("清空最近") { session.clearRecents() } }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    private func placeRow(_ place: SavedPlace, favorite: Bool) -> some View {
        Button {
            onSelect(place)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: favorite ? "star.fill" : "clock.fill")
                    .foregroundStyle(favorite ? .yellow : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name).foregroundStyle(.primary).lineLimit(1)
                    Text(String(format: "%.6f, %.6f", place.latitude, place.longitude))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
