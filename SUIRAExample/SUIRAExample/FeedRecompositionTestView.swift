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
            Section("Фильтры") {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Toggle("Favorites only", isOn: $showFavoritesOnly)

                Button("Shuffle progress") {
                    items = items.map { item in
                        var updated = item
                        updated.progress = Double.random(in: 0...1)
                        return updated
                    }
                }
                .buttonStyle(.bordered)
            }

            Section("Feed") {
                ForEach(filteredItems) { item in
                    FeedRow(
                        item: item,
                        onToggleFavorite: { toggleFavorite(for: item.id) },
                        onAdvance: { advanceProgress(for: item.id) }
                    )
                }
            }
        }
        .navigationTitle("Feed Test")
        .trackRecomposition("FeedRecompositionTestView")
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
            }

            ProgressView(value: item.progress)

            HStack {
                Text("\(Int(item.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Advance", action: onAdvance)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationView {
        FeedRecompositionTestView()
    }
}
