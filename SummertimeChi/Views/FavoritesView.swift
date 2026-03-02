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
                    .presentationDetents([.fraction(0.55), .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear { viewModel.loadFavorites() }
            .task { await viewModel.loadWeather() }
        }
    }

    // MARK: - Favorites List

    private var favoritesList: some View {
        List {
            if viewModel.isLoadingWeather || viewModel.weather != nil {
                Section {
                    weatherCard
                }
            }
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

    // MARK: - Weather Card

    @ViewBuilder
    private var weatherCard: some View {
        if viewModel.isLoadingWeather {
            HStack {
                ProgressView()
                Text("Loading weather…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else if let wx = viewModel.weather {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Chicago Weather", systemImage: weatherIcon(for: wx))
                        .font(.headline)
                    Spacer()
                    if let temp = wx.temperatureFahrenheit {
                        Text("\(Int(temp))°F")
                            .font(.title2.bold())
                    }
                }

                HStack(spacing: 20) {
                    Label("\(Int(wx.cloudCoverFraction * 100))% clouds", systemImage: "cloud")
                    Text(wx.conditionDescription)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(patioSuitability(for: wx))
                    .font(.subheadline.bold())
                    .foregroundStyle(suitabilityColor(for: wx))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(suitabilityColor(for: wx).opacity(0.15), in: Capsule())
            }
            .padding(.vertical, 6)
        }
    }

    private func weatherIcon(for wx: WeatherService.WeatherConditions) -> String {
        if wx.cloudCoverFraction > 0.8 { return "cloud.fill" }
        if wx.cloudCoverFraction > 0.4 { return "cloud.sun.fill" }
        return "sun.max.fill"
    }

    private func patioSuitability(for wx: WeatherService.WeatherConditions) -> String {
        if wx.cloudCoverFraction > 0.8 { return "Overcast — shade likely everywhere" }
        if wx.cloudCoverFraction > 0.4 { return "Partly cloudy — good patio weather" }
        return "Sunny — check shade status per bar"
    }

    private func suitabilityColor(for wx: WeatherService.WeatherConditions) -> Color {
        if wx.cloudCoverFraction > 0.8 { return .blue }
        if wx.cloudCoverFraction > 0.4 { return .orange }
        return .yellow
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingWeather || viewModel.weather != nil {
                List {
                    Section { weatherCard }
                }
                .listStyle(.plain)
                .frame(height: 100)
            }

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
}

#Preview {
    FavoritesView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
