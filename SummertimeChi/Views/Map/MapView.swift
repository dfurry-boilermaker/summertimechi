import SwiftUI
import MapKit
import CoreData

struct MapView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: MapViewModel
    @State private var selectedBar: Bar?
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 41.8827, longitude: -87.6233),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    init() {
        _viewModel = StateObject(wrappedValue: MapViewModel(
            context: PersistenceController.shared.container.viewContext
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    ForEach(viewModel.bars) { bar in
                        Annotation(bar.name, coordinate: bar.coordinate) {
                            BarAnnotationView(bar: bar) {
                                selectedBar = bar
                            }
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)
                .onMapCameraChange(frequency: .onEnd) { context in
                    let region = context.region
                    let visible = viewModel.visibleBars(in: region)
                    Task { await viewModel.updateSunStatus(for: visible) }
                }

                if viewModel.isLoading {
                    ProgressView("Loading bars…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                VStack {
                    Spacer()
                    refreshButton
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle("SummertimeChi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refreshData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $selectedBar) { (bar: Bar) in
                BarDetailView(bar: bar)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
        }
        .onAppear {
            viewModel.loadBars()
            // Auto-refresh on first launch when the local cache is empty
            if viewModel.bars.isEmpty {
                Task { await viewModel.refreshData() }
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.refreshData() }
        } label: {
            Label("Refresh Bars", systemImage: "arrow.clockwise.circle.fill")
                .font(.subheadline.bold())
        }
        .buttonStyle(.borderedProminent)
        .tint(.yellow)
        .foregroundStyle(.black)
    }
}

#Preview {
    MapView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
