import SwiftUI

/// Color-coded map pin for a bar, reflecting its current sun/shade status.
struct BarAnnotationView: View {
    let bar: Bar
    let onTap: () -> Void

    private var status: SunStatus {
        bar.cachedSunStatus ?? .unknown
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                pinBody
                pinStem
            }
        }
        .buttonStyle(.plain)
    }

    private var pinBody: some View {
        ZStack {
            Circle()
                .fill(status.annotationColor)
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)

            Image(systemName: status.systemImageName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pinForegroundColor)
        }
    }

    private var pinStem: some View {
        Triangle()
            .fill(status.annotationColor)
            .frame(width: 10, height: 8)
    }

    private var pinForegroundColor: Color {
        switch status {
        case .sunlit, .partialSun: return .black
        default:                   return .white
        }
    }
}

// MARK: - Pin Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(SunStatus.allCases, id: \.self) { status in
            BarAnnotationView(
                bar: Bar(
                    id: UUID(), name: "Test", coordinate: .init(latitude: 0, longitude: 0),
                    yelpRating: 0, yelpReviewCount: 0, hasPatioConfirmed: true,
                    dataSourceMask: .osm, isFavorite: false, sunAlertsEnabled: false,
                    cachedSunStatus: status
                ),
                onTap: {}
            )
        }
    }
    .padding()
}
