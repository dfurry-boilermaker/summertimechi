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
                    detailInfoCard
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

            if let subtext = viewModel.statusSubtext {
                Label(subtext, systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12 AM" }
        if h == 12 { return "12 PM" }
        return h < 12 ? "\(h) AM" : "\(h - 12) PM"
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Timeline")
                .font(.headline)

            if let timeline = viewModel.sunTimeline {
                SunTimelineView(
                    timeline: timeline,
                    openHour: viewModel.bar.openHour,
                    closeHour: viewModel.bar.closeHour
                )
            } else {
                ProgressView("Calculating…")
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            timelineLegend
        }
    }

    private var timelineLegend: some View {
        HStack(spacing: 12) {
            legendItem(color: .yellow, label: "Sun")
            legendItem(color: .gray, label: "Shade")
            legendItem(color: .indigo, label: "Night")
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 2, height: 10)
                Text("Now")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if viewModel.bar.openHour != nil {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green)
                        .frame(width: 2, height: 10)
                    Text("Open")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red)
                        .frame(width: 2, height: 10)
                    Text("Close")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Detail Info Card

    private var detailInfoCard: some View {
        VStack(spacing: 0) {
            if let address = viewModel.bar.address {
                infoRow(
                    icon: "mappin.circle.fill",
                    iconColor: .red,
                    title: address,
                    subtitle: viewModel.bar.neighborhood
                )
            }

            if let open = viewModel.bar.openHour, let close = viewModel.bar.closeHour {
                if viewModel.bar.address != nil { infoDivider }
                let currentHour = Calendar.current.component(.hour, from: Date())
                let isOpen = viewModel.bar.isOpen(atHour: currentHour)
                infoRow(
                    icon: "clock.fill",
                    iconColor: isOpen ? .green : .red,
                    title: "\(formatHour(open)) – \(formatHour(close))",
                    subtitle: isOpen ? "Open now" : "Closed now",
                    subtitleColor: isOpen ? .green : .red
                )
            }

            if let text = viewModel.formattedSunlight {
                infoDivider
                infoRow(
                    icon: "sun.max.fill",
                    iconColor: .yellow,
                    title: text,
                    subtitle: viewModel.sunlightFraction.map { "\(Int($0 * 100))% of open hours in daylight" }
                )
            }
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(
        icon: String, iconColor: Color,
        title: String, subtitle: String?,
        subtitleColor: Color = .secondary
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                if let sub = subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var infoDivider: some View {
        Divider().padding(.leading, 52)
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
