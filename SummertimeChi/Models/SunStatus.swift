import SwiftUI

/// The current sun/shade status of a bar's outdoor patio.
enum SunStatus: String, CaseIterable {
    case sunlit       = "sunlit"
    case shaded       = "shaded"
    case cloudy       = "cloudy"
    case belowHorizon = "belowHorizon"
    case unknown      = "unknown"

    var displayName: String {
        switch self {
        case .sunlit:       return "In the Sun"
        case .shaded:       return "In the Shade"
        case .cloudy:       return "Cloudy"
        case .belowHorizon: return "Sun Below Horizon"
        case .unknown:      return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .sunlit:       return .yellow
        case .shaded:       return Color(white: 0.5)
        case .cloudy:       return Color(white: 0.5)
        case .belowHorizon: return .indigo
        case .unknown:      return .gray
        }
    }

    var systemImageName: String {
        switch self {
        case .sunlit:       return "sun.max.fill"
        case .shaded:       return "building.2.fill"
        case .cloudy:       return "cloud.fill"
        case .belowHorizon: return "moon.stars.fill"
        case .unknown:      return "questionmark.circle"
        }
    }

    var annotationColor: Color {
        switch self {
        case .sunlit:       return .yellow
        case .shaded:       return Color(white: 0.45)
        case .cloudy:       return Color(white: 0.45)
        case .belowHorizon: return .indigo
        case .unknown:      return .gray
        }
    }
}
