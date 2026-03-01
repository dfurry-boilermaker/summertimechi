import SwiftUI

/// Displays a Chicago DOT webcam snapshot near the bar, if available.
/// This is a supplementary feature — many bars will show the "no camera" state.
struct CameraFeedView: View {
    let snapshot: Data?
    let cameraName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nearby Camera")
                .font(.headline)

            if let imageData = snapshot, let uiImage = UIImage(data: imageData) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let name = cameraName {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Source: Chicago DOT • Best-effort, not authoritative")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                noCameraView
            }
        }
    }

    private var noCameraView: some View {
        HStack {
            Image(systemName: "video.slash")
                .foregroundStyle(.secondary)
            Text("No camera available near this location")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

#Preview {
    VStack(spacing: 20) {
        CameraFeedView(snapshot: nil, cameraName: nil)
        CameraFeedView(snapshot: nil, cameraName: "Wrigleyville - Clark & Addison")
    }
    .padding()
}
