import SwiftUI
import CoreData

struct BarDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: BarDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(bar: Bar) {
        _viewModel = StateObject(wrappedValue: BarDetailViewModel(
            bar: bar,
            context: PersistenceController.shared.container.viewContext
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusHeader
                    Divider()
                    timelineSection
                }
                .padding()
            }
            .navigationTitle(viewModel.bar.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        favoriteButton
                        alertToggleButton
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await viewModel.loadAll() }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: viewModel.currentStatus.systemImageName)
                    .font(.title2)
                    .foregroundStyle(viewModel.currentStatus.color)
                Text(viewModel.currentStatus.displayName)
                    .font(.title2.bold())
                    .foregroundStyle(viewModel.currentStatus.color)
                Spacer()
                if viewModel.isLoadingTimeline {
                    ProgressView()
                }
            }

            if let address = viewModel.bar.address {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let transition = viewModel.nextTransitionDescription {
                Label(transition, systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Timeline")
                .font(.headline)
            if let timeline = viewModel.sunTimeline {
                SunTimelineView(timeline: timeline)
            } else {
                ProgressView("Calculating…")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Toolbar Buttons

    private var favoriteButton: some View {
        Button {
            viewModel.toggleFavorite()
        } label: {
            Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(viewModel.isFavorite ? .red : .gray)
        }
    }

    private var alertToggleButton: some View {
        Button {
            viewModel.toggleSunAlerts()
        } label: {
            Image(systemName: viewModel.sunAlertsEnabled ? "bell.fill" : "bell")
                .foregroundStyle(viewModel.sunAlertsEnabled ? .yellow : .gray)
        }
    }
}

#Preview {
    BarDetailView(bar: Bar(
        id: UUID(), name: "Gman Tavern",
        coordinate: .init(latitude: 41.9472, longitude: -87.6539),
        neighborhood: "Wrigleyville",
        yelpRating: 4.5, yelpReviewCount: 312,
        hasPatioConfirmed: true, dataSourceMask: .osm,
        isFavorite: false, sunAlertsEnabled: false,
        cachedSunStatus: .sunlit
    ))
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
