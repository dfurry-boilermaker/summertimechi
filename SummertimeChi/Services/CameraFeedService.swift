import Foundation
import CoreLocation

/// Represents a Chicago DOT traffic/street camera with a live JPEG snapshot.
struct ChicagoCamera: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let snapshotURL: URL
}

/// Protocol stub for social feed integration (future official API hookup only).
/// Do NOT scrape Instagram/Meta — TOS violation.
protocol SocialFeedService {
    func fetchRecentPosts(near coordinate: CLLocationCoordinate2D) async -> [SocialPost]
}

struct SocialPost {
    let id: String
    let imageURL: URL?
    let caption: String?
    let timestamp: Date
    let source: String
}

/// Fetches Chicago DOT webcam thumbnails for display near bars.
/// Camera data is sourced from a manually curated JSON list.
/// This is a supplementary, best-effort feature; many bars will have no nearby camera.
final class CameraFeedService {
    static let shared = CameraFeedService()
    private init() {}

    private var cameras: [ChicagoCamera] = []
    private var loaded = false

    // MARK: - Public API

    /// Returns the nearest camera within 500m of a given coordinate, if any.
    func nearestCamera(to coordinate: CLLocationCoordinate2D) -> ChicagoCamera? {
        ensureLoaded()
        let maxDistanceMeters = 500.0
        return cameras
            .map { camera -> (ChicagoCamera, Double) in
                let dist = distance(from: coordinate, to: camera.coordinate)
                return (camera, dist)
            }
            .filter { $0.1 <= maxDistanceMeters }
            .min(by: { $0.1 < $1.1 })
            .map { $0.0 }
    }

    /// Fetches the latest JPEG snapshot for a camera.
    func fetchSnapshot(for camera: ChicagoCamera) async -> Data? {
        var request = URLRequest(url: camera.snapshotURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        return try? await URLSession.shared.data(for: request).0
    }

    // MARK: - Camera Data Loading

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        cameras = builtinCameras()
    }

    /// Curated list of Chicago DOT cameras near popular bar corridors.
    /// Source: chicago.gov/city/en/depts/cdot.html traffic cameras
    private func builtinCameras() -> [ChicagoCamera] {
        // Each entry: id, name, lat, lon, snapshot URL
        let cameraData: [(String, String, Double, Double, String)] = [
            ("chi-001", "Wrigleyville - Clark & Addison",           41.9467, -87.6558, "https://www.chicago-webcams.com/snapshots/clark-addison.jpg"),
            ("chi-002", "Wicker Park - Milwaukee & North",          41.9095, -87.6779, "https://www.chicago-webcams.com/snapshots/milwaukee-north.jpg"),
            ("chi-003", "River North - Rush & Division",             41.9036, -87.6281, "https://www.chicago-webcams.com/snapshots/rush-division.jpg"),
            ("chi-004", "Logan Square - Milwaukee & Logan",         41.9228, -87.7016, "https://www.chicago-webcams.com/snapshots/milwaukee-logan.jpg"),
            ("chi-005", "Pilsen - 18th & Halsted",                  41.8575, -87.6468, "https://www.chicago-webcams.com/snapshots/18th-halsted.jpg"),
            ("chi-006", "Lincoln Park - Halsted & Armitage",        41.9187, -87.6487, "https://www.chicago-webcams.com/snapshots/halsted-armitage.jpg"),
            ("chi-007", "West Loop - Randolph & Halsted",           41.8836, -87.6484, "https://www.chicago-webcams.com/snapshots/randolph-halsted.jpg"),
            ("chi-008", "Andersonville - Clark & Catalpa",          41.9802, -87.6692, "https://www.chicago-webcams.com/snapshots/clark-catalpa.jpg"),
            ("chi-009", "Hyde Park - 55th & Lake Park",             41.7951, -87.5878, "https://www.chicago-webcams.com/snapshots/55th-lakepark.jpg"),
            ("chi-010", "Ukrainian Village - Chicago & Damen",      41.8958, -87.6779, "https://www.chicago-webcams.com/snapshots/chicago-damen.jpg"),
        ]

        return cameraData.compactMap { (id, name, lat, lon, urlStr) in
            guard let url = URL(string: urlStr) else { return nil }
            return ChicagoCamera(
                id: id,
                name: name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                snapshotURL: url
            )
        }
    }

    // MARK: - Distance

    private func distance(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }
}
