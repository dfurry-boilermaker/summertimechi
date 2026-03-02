import Foundation
import CoreLocation

/// Output of the solar position calculation.
struct SolarPosition {
    /// Compass bearing of the sun in degrees (0 = North, 90 = East, 180 = South, 270 = West).
    let azimuth: Double
    /// Angle of the sun above the horizon in degrees. Negative means below horizon.
    let altitude: Double
    /// `true` when the sun is above the horizon (altitude > 0).
    var isAboveHorizon: Bool { altitude > 0 }
}

/// Computes the solar position using the NOAA Solar Calculator algorithm.
/// Reference: https://gml.noaa.gov/grad/solcalc/calcdetails.html
///
/// All internal angles are in degrees unless the variable name ends in `Rad`.
final class SolarCalculatorService {
    static let shared = SolarCalculatorService()
    private init() {}

    // MARK: - Public API

    /// Returns the solar position for a given location and time.
    func solarPosition(at coordinate: CLLocationCoordinate2D, date: Date) -> SolarPosition {
        let jd = julianDay(from: date)
        return solarPosition(latitude: coordinate.latitude, longitude: coordinate.longitude, julianDay: jd)
    }

    /// Returns the solar position for given lat/lon at a specific Julian Day number.
    func solarPosition(latitude: Double, longitude: Double, julianDay jd: Double) -> SolarPosition {
        // Julian Century
        let T = (jd - 2451545.0) / 36525.0

        // Geometric mean longitude of the sun (degrees)
        let L0 = normalizeAngle(280.46646 + T * (36000.76983 + T * 0.0003032))

        // Geometric mean anomaly of the sun (degrees)
        let M = normalizeAngle(357.52911 + T * (35999.05029 - T * 0.0001537))
        let Mrad = toRadians(M)

        // Equation of center
        let C = (1.914602 - T * (0.004817 + 0.000014 * T)) * sin(Mrad)
               + (0.019993 - 0.000101 * T) * sin(2 * Mrad)
               + 0.000289 * sin(3 * Mrad)

        // Sun's true longitude (degrees)
        let sunLon = L0 + C

        // Apparent longitude (degrees) — corrected for nutation and aberration
        let omega = 125.04 - 1934.136 * T
        let lambda = sunLon - 0.00569 - 0.00478 * sin(toRadians(omega))

        // Obliquity of the ecliptic (degrees)
        let epsilon0 = 23.0 + (26.0 + (21.448 - T * (46.8150 + T * (0.00059 - T * 0.001813))) / 60.0) / 60.0
        let epsilon = epsilon0 + 0.00256 * cos(toRadians(omega))

        // Sun's right ascension (degrees, 0-360)
        let sinLambda = sin(toRadians(lambda))
        let cosEpsilon = cos(toRadians(epsilon))
        var rightAscension = toDegrees(atan2(cosEpsilon * sinLambda, cos(toRadians(lambda))))
        rightAscension = normalizeAngle(rightAscension)

        // Sun's declination (degrees)
        let declination = toDegrees(asin(sin(toRadians(epsilon)) * sinLambda))

        // Equation of time (minutes)
        let y = tan(toRadians(epsilon / 2.0)) * tan(toRadians(epsilon / 2.0))
        let eqOfTime = 4.0 * toDegrees(
            y * sin(2.0 * toRadians(L0))
            - 2.0 * eccentricity(T) * sin(Mrad)
            + 4.0 * eccentricity(T) * y * sin(Mrad) * cos(2.0 * toRadians(L0))
            - 0.5 * y * y * sin(4.0 * toRadians(L0))
            - 1.25 * eccentricity(T) * eccentricity(T) * sin(2.0 * Mrad)
        )

        // True solar time (minutes)
        let minutesUTC = utcMinutes(from: julianDayToDate(jd))
        let trueSolarTime = fmod(minutesUTC + eqOfTime + 4.0 * longitude, 1440.0)

        // Hour angle (degrees)
        var hourAngle = trueSolarTime / 4.0 - 180.0
        if hourAngle < -180 { hourAngle += 360.0 }

        // Solar zenith angle (degrees)
        let latRad = toRadians(latitude)
        let decRad = toRadians(declination)
        let haRad  = toRadians(hourAngle)

        let cosZenith = sin(latRad) * sin(decRad)
                      + cos(latRad) * cos(decRad) * cos(haRad)
        var zenith = toDegrees(acos(min(max(cosZenith, -1.0), 1.0)))

        // Atmospheric refraction correction (degrees)
        let apparentElevation = 90.0 - zenith
        let refraction = atmosphericRefraction(elevation: apparentElevation)
        zenith -= refraction

        let elevation = 90.0 - zenith

        // Azimuth (degrees, 0 = North)
        let sinZenith = sin(toRadians(zenith))
        var azimuth: Double
        if sinZenith == 0 {
            azimuth = 0
        } else {
            let cosAz = -(sin(latRad) * cosZenith - sin(decRad)) / (cos(latRad) * sinZenith)
            azimuth = toDegrees(acos(min(max(cosAz, -1.0), 1.0)))
            if hourAngle > 0 {
                azimuth = normalizeAngle(azimuth + 180.0)
            } else {
                azimuth = normalizeAngle(540.0 - azimuth)
            }
        }

        return SolarPosition(azimuth: azimuth, altitude: elevation)
    }

    // MARK: - Julian Day

    /// Converts a `Date` to a Julian Day number (J2000 epoch).
    func julianDay(from date: Date) -> Double {
        return date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// Converts a Julian Day back to a Date.
    func julianDayToDate(_ jd: Double) -> Date {
        return Date(timeIntervalSince1970: (jd - 2440587.5) * 86400.0)
    }

    // MARK: - Sunrise / Sunset

    /// Returns approximate sunrise and sunset times (in UTC) for a given location and date.
    func sunriseSunset(at coordinate: CLLocationCoordinate2D, date: Date) -> (sunrise: Date?, sunset: Date?) {
        // Use binary search to find when altitude crosses 0
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        let sunrise = binarySearchTransition(
            coordinate: coordinate,
            startDate: startOfDay,
            endDate: startOfDay.addingTimeInterval(12 * 3600),
            risingNotSetting: true
        )
        let sunset = binarySearchTransition(
            coordinate: coordinate,
            startDate: startOfDay.addingTimeInterval(12 * 3600),
            endDate: startOfDay.addingTimeInterval(24 * 3600),
            risingNotSetting: false
        )
        return (sunrise, sunset)
    }

    private func binarySearchTransition(
        coordinate: CLLocationCoordinate2D,
        startDate: Date,
        endDate: Date,
        risingNotSetting: Bool
    ) -> Date? {
        var lo = startDate.timeIntervalSince1970
        var hi = endDate.timeIntervalSince1970

        let startPos = solarPosition(at: coordinate, date: startDate)
        let endPos   = solarPosition(at: coordinate, date: endDate)

        // Check if transition exists in this window
        if risingNotSetting && (startPos.altitude >= 0 || endPos.altitude < 0) { return nil }
        if !risingNotSetting && (startPos.altitude < 0 || endPos.altitude >= 0) { return nil }

        for _ in 0..<50 {
            let mid = (lo + hi) / 2
            let midDate = Date(timeIntervalSince1970: mid)
            let pos = solarPosition(at: coordinate, date: midDate)
            if abs(pos.altitude) < 0.01 { return midDate }
            if risingNotSetting {
                if pos.altitude < 0 { lo = mid } else { hi = mid }
            } else {
                if pos.altitude >= 0 { lo = mid } else { hi = mid }
            }
        }
        return Date(timeIntervalSince1970: (lo + hi) / 2)
    }

    // MARK: - Private Helpers

    private func eccentricity(_ T: Double) -> Double {
        0.016708634 - T * (0.000042037 + 0.0000001267 * T)
    }

    private func atmosphericRefraction(elevation: Double) -> Double {
        guard elevation > -0.575 else {
            return -20.774 / 3600.0
        }
        if elevation > 85.0 { return 0.0 }
        let h = elevation
        if h > 5.0 {
            return (58.1 / tan(toRadians(h)) - 0.07 / pow(tan(toRadians(h)), 3) + 0.000086 / pow(tan(toRadians(h)), 5)) / 3600.0
        } else if h > -0.575 {
            return (1735.0 + h * (-518.2 + h * (103.4 + h * (-12.79 + h * 0.711)))) / 3600.0
        }
        return 0.0
    }

    private func utcMinutes(from date: Date) -> Double {
        // Seconds elapsed since the most recent UTC midnight.
        // timeIntervalSince1970 is always UTC-based, so no timezone conversion needed.
        return date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400.0) / 60.0
    }

    // MARK: - Angle Utilities

    func toRadians(_ degrees: Double) -> Double { degrees * .pi / 180.0 }
    func toDegrees(_ radians: Double) -> Double { radians * 180.0 / .pi }
    func normalizeAngle(_ angle: Double) -> Double {
        var result = angle.truncatingRemainder(dividingBy: 360.0)
        if result < 0 { result += 360.0 }
        return result
    }
}
