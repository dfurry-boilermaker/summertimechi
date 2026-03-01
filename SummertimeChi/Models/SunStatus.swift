import SwiftUI

/// The current sun/shade status of a bar's outdoor patio.
enum SunStatus: String, CaseIterable {
    case sunlit      = "sunlit"
    case shaded      = "shaded"
    case partialSun  = "partialSun"
    case cloudy      = "cloudy"
    case belowHorizon = "belowHorizon"
    case unknown     = "unknown"

    var displayName: String {
        switch self {
        case .sunlit:       return "In the Sun"
        case .shaded:       return "In the Shade"
        case .partialSun:   return "Partial Sun"
        case .cloudy:       return "Cloudy"
        case .belowHorizon: return "Sun Below Horizon"
        case .unknown:      return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .sunlit:       return .yellow
        case .shaded:       return Color(white: 0.5)
        case .partialSun:   return .orange
        case .cloudy:       return .blue
        case .belowHorizon: return Color(white: 0.3)
        case .unknown:      return .gray
        }
    }

    var systemImageName: String {
        switch self {
        case .sunlit:       return "sun.max.fill"
        case .shaded:       return "cloud.fill"
        case .partialSun:   return "cloud.sun.fill"
        case .cloudy:       return "cloud.fill"
        case .belowHorizon: return "moon.stars.fill"
        case .unknown:      return "questionmark.circle"
        }
    }

    var annotationColor: Color {
        switch self {
        case .sunlit:       return .yellow
        case .shaded:       return Color(white: 0.45)
        case .partialSun:   return .orange
        case .cloudy:       return .blue
        case .belowHorizon: return Color(white: 0.25)
        case .unknown:      return .gray
        }
    }
}
