import SwiftUI
import CoreData

struct SearchView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var searchText = ""
    @State private var selectedFilter: SearchFilter = .all
    @State private var selectedBar: Bar?

    enum SearchFilter: String, CaseIterable {
        case all        = "All"
        case inSunNow   = "In Sun Now"
        case inShade    = "In Shade"
        case favorites  = "Favorites"
    }

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BarEntity.name, ascending: true)],
        animation: .default
    )
    private var barEntities: FetchedResults<BarEntity>

    private var filteredBars: [Bar] {
        let allBars = barEntities.map { Bar(entity: $0) }

        return allBars.filter { bar in
            // Text filter
            let matchesText = searchText.isEmpty ||
                bar.name.localizedCaseInsensitiveContains(searchText) ||
                (bar.neighborhood?.localizedCaseInsensitiveContains(searchText) ?? false)

            // Category filter
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .inSunNow:
                matchesFilter = bar.cachedSunStatus == .sunlit || bar.cachedSunStatus == .partialSun
            case .inShade:
                matchesFilter = bar.cachedSunStatus == .shaded
            case .favorites:
                matchesFilter = bar.isFavorite
            }

            return matchesText && matchesFilter
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChips
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                if filteredBars.isEmpty {
                    emptyState
                } else {
                    barList
                }
            }
            .navigationTitle("Search Bars")
            .searchable(text: $searchText, prompt: "Bar name or neighborhood…")
            .sheet(item: $selectedBar) { (bar: Bar) in
                BarDetailView(bar: bar)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases, id: \.self) { filter in
                    FilterChip(title: filter.rawValue, isSelected: selectedFilter == filter) {
                        selectedFilter = filter
                    }
                }
            }
        }
    }

    // MARK: - Bar List

    private var barList: some View {
        List(filteredBars) { bar in
            BarListRow(bar: bar)
                .contentShape(Rectangle())
                .onTapGesture { selectedBar = bar }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No bars match the current filter." : "No results for \"\(searchText)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Bar List Row

struct BarListRow: View {
    let bar: Bar

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((bar.cachedSunStatus ?? .unknown).annotationColor)
                    .frame(width: 36, height: 36)
                Image(systemName: (bar.cachedSunStatus ?? .unknown).systemImageName)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(bar.name)
                    .font(.subheadline.bold())
                if let neighborhood = bar.neighborhood {
                    Text(neighborhood)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let status = bar.cachedSunStatus {
                    Text(status.displayName)
                        .font(.caption)
                        .foregroundStyle(status.color)
                }
            }

            Spacer()

            if bar.yelpRating > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", bar.yelpRating))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.yellow : Color(white: 0.15))
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SearchView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
