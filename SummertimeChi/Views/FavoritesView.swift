import SwiftUI
import CoreData

struct FavoritesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: FavoritesViewModel
    @State private var selectedBar: Bar?

    init() {
        _viewModel = StateObject(wrappedValue: FavoritesViewModel(
            context: PersistenceController.shared.container.viewContext
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.favoriteBars.isEmpty {
                    emptyState
                } else {
                    favoritesList
                }
            }
            .navigationTitle("Favorites")
            .sheet(item: $selectedBar) { (bar: Bar) in
                BarDetailView(bar: bar)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear { viewModel.loadFavorites() }
        }
    }

    // MARK: - Favorites List

    private var favoritesList: some View {
        List {
            ForEach(viewModel.favoriteBars) { bar in
                HStack {
                    BarListRow(bar: bar)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedBar = bar }

                    // Sun alert toggle
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { bar.sunAlertsEnabled },
                            set: { _ in viewModel.toggleSunAlert(for: bar) }
                        )
                    )
                    .labelsHidden()
                    .tint(.yellow)
                    .frame(width: 50)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    viewModel.removeFavorite(viewModel.favoriteBars[index])
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No favorites yet")
                .font(.headline)
            Text("Tap the heart icon on any bar to save it here and get sun alerts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FavoritesView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
