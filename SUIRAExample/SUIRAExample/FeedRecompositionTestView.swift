import SwiftUI
import SUIRA

struct FeedRecompositionTestView: View {
    struct FeedItem: Identifiable, Hashable {
        let id: UUID
        var title: String
        var subtitle: String
        var isFavorite: Bool
        var progress: Double
    }

    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var items: [FeedItem] = [
        FeedItem(id: UUID(), title: "Alpha task", subtitle: "Sync design tokens", isFavorite: false, progress: 0.2),
        FeedItem(id: UUID(), title: "Beta release", subtitle: "Prepare release notes", isFavorite: true, progress: 0.75),
        FeedItem(id: UUID(), title: "Gamma QA", subtitle: "Run smoke tests", isFavorite: false, progress: 0.45),
        FeedItem(id: UUID(), title: "Delta analytics", subtitle: "Inspect recompositions", isFavorite: true, progress: 0.9),
        FeedItem(id: UUID(), title: "Epsilon onboarding", subtitle: "Update example app", isFavorite: false, progress: 0.1)
    ]

    private var filteredItems: [FeedItem] {
        items.filter { item in
            let matchesSearch = searchText.isEmpty
                || item.title.localizedCaseInsensitiveContains(searchText)
                || item.subtitle.localizedCaseInsensitiveContains(searchText)
            let matchesFavorite = !showFavoritesOnly || item.isFavorite
            return matchesSearch && matchesFavorite
        }
    }

    var body: some View {
        List {
            FeedFiltersSection(
                searchText: $searchText,
                showFavoritesOnly: $showFavoritesOnly,
                onShuffleProgress: shuffleProgress
            )

            FeedItemsSection(
                items: filteredItems,
                onToggleFavorite: toggleFavorite,
                onAdvance: advanceProgress
            )
        }
        .navigationTitle("Feed Test")
        .trackRecomposition("FeedRecompositionTestView")
    }

    private func shuffleProgress() {
        items = items.map { item in
            var updated = item
            updated.progress = Double.random(in: 0...1)
            return updated
        }
    }

    private func toggleFavorite(for id: UUID) {
        items = items.map { item in
            guard item.id == id else { return item }
            var updated = item
            updated.isFavorite.toggle()
            return updated
        }
    }

    private func advanceProgress(for id: UUID) {
        items = items.map { item in
            guard item.id == id else { return item }
            var updated = item
            updated.progress = min(updated.progress + 0.1, 1)
            return updated
        }
    }
}

private struct FeedFiltersSection: View {
    @Binding var searchText: String
    @Binding var showFavoritesOnly: Bool
    let onShuffleProgress: () -> Void

    var body: some View {
        Section("Фильтры") {
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .trackRecomposition("Feed.Filters.SearchField")

            Toggle("Favorites only", isOn: $showFavoritesOnly)
                .trackRecomposition("Feed.Filters.FavoritesToggle")

            Button("Shuffle progress", action: onShuffleProgress)
                .buttonStyle(.bordered)
                .trackRecomposition("Feed.Filters.ShuffleButton")
        }
        .trackRecomposition("Feed.Filters")
    }
}

private struct FeedItemsSection: View {
    let items: [FeedRecompositionTestView.FeedItem]
    let onToggleFavorite: (UUID) -> Void
    let onAdvance: (UUID) -> Void

    var body: some View {
        Section("Feed") {
            ForEach(items) { item in
                FeedRow(
                    item: item,
                    onToggleFavorite: { onToggleFavorite(item.id) },
                    onAdvance: { onAdvance(item.id) }
                )
            }
        }
        .trackRecomposition("Feed.List")
    }
}

private struct FeedRow: View {
    let item: FeedRecompositionTestView.FeedItem
    let onToggleFavorite: () -> Void
    let onAdvance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onToggleFavorite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .trackRecomposition("Feed.Row.\(item.title).FavoriteButton")
            }

            ProgressView(value: item.progress)
                .trackRecomposition("Feed.Row.\(item.title).Progress")

            HStack {
                Text("\(Int(item.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .trackRecomposition("Feed.Row.\(item.title).ProgressText")

                Spacer()

                Button("Advance", action: onAdvance)
                    .buttonStyle(.borderedProminent)
                    .trackRecomposition("Feed.Row.\(item.title).AdvanceButton")
            }
        }
        .padding(.vertical, 6)
        .trackRecomposition("Feed.Row.\(item.title)")
    }
}

#Preview {
    NavigationView {
        FeedRecompositionTestView()
    }
}
