import Foundation

// Solar position and lunar illumination adapted from SunCalc 1.9.0.
// See Resources/SunCalc-LICENSE.txt for the copyright and license.
nonisolated enum TodaySkyAstronomy {
    struct Coordinates: Equatable {
        let latitude: Double
        let longitude: Double
    }

    struct Moon: Equatable {
        let illumination: Double
        let isWaxing: Bool

        var isFull: Bool { illumination >= 0.97 }
        var isNew: Bool { illumination <= 0.03 }

        var starCount: Int {
            if isFull { return 0 }
            if isNew { return 18 }
            return Int((18 * pow(1 - illumination, 0.87)).rounded())
        }
    }

    struct TrackPoint: Equatable {
        /// Position along the visible arc, from the right horizon to the left horizon.
        let progress: Double
        let height: Double
    }

    struct Sky: Equatable {
        let sunAltitude: Double
        let isMorning: Bool
        let moon: Moon
        let sunTrack: TrackPoint?
        let moonTrack: TrackPoint?

        var starVisibility: Double { min(max((-sunAltitude - 6) / 12, 0), 1) }
    }

    private struct EquatorialPosition {
        let rightAscension: Double
        let declination: Double

        init(longitude: Double, latitude: Double) {
            let obliquity = 23.4397 * TodaySkyAstronomy.radians
            rightAscension = atan2(sin(longitude) * cos(obliquity) - tan(latitude) * sin(obliquity), cos(longitude))
            declination = asin(sin(latitude) * cos(obliquity) + cos(latitude) * sin(obliquity) * sin(longitude))
        }
    }

    private static let radians = Double.pi / 180
    private static let clockAltitudes: [(hour: Double, altitude: Double)] = [
        (0, -18), (5, -18), (5.5, -6), (6, 0), (7.5, 12), (12, 45),
        (16.5, 12), (18, 0), (18.5, -6), (19, -18), (24, -18)
    ]

    static func sky(at date: Date, coordinates: Coordinates?, calendar: Calendar = .autoupdatingCurrent) -> Sky {
        let days = daysSinceJ2000(date)
        let sun = solarPosition(days: days)
        let lunarPosition = lunarPosition(days: days)
        let moon = lunarPhase(sun: sun, moon: lunarPosition.position, moonDistance: lunarPosition.distance)
        if let coordinates {
            let siderealTime = (280.16 + 360.9856235 * days + coordinates.longitude) * radians
            let sunHourAngle = siderealTime - sun.rightAscension
            let latitude = coordinates.latitude * radians
            let solar = horizonPosition(hourAngle: sunHourAngle, latitude: latitude, declination: sun.declination)
            let lunar = horizonPosition(hourAngle: siderealTime - lunarPosition.position.rightAscension,
                                        latitude: latitude, declination: lunarPosition.position.declination)
            return Sky(sunAltitude: solar.altitude, isMorning: sin(sunHourAngle) < 0, moon: moon,
                       sunTrack: solar.track, moonTrack: moon.isNew ? nil : lunar.track)
        }

        let local = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = Double(local.hour ?? 0) + Double(local.minute ?? 0) / 60 + Double(local.second ?? 0) / 3600
        let upperIndex = clockAltitudes.firstIndex { $0.hour > hour } ?? (clockAltitudes.count - 1)
        let lower = clockAltitudes[upperIndex - 1]
        let upper = clockAltitudes[upperIndex]
        let progress = (hour - lower.hour) / (upper.hour - lower.hour)
        // Without a location, use the local clock as an equatorial sky for the two arcs.
        let clockHourAngle = (hour - 12) * .pi / 12
        let solar = horizonPosition(hourAngle: clockHourAngle, latitude: 0, declination: 0)
        let lunar = horizonPosition(hourAngle: clockHourAngle + sun.rightAscension - lunarPosition.position.rightAscension,
                                    latitude: 0, declination: lunarPosition.position.declination)
        return Sky(sunAltitude: lower.altitude + (upper.altitude - lower.altitude) * progress,
                   isMorning: hour < 12, moon: moon,
                   sunTrack: solar.track, moonTrack: moon.isNew ? nil : lunar.track)
    }

    private static func horizonPosition(hourAngle: Double, latitude: Double,
                                        declination: Double) -> (altitude: Double, track: TrackPoint?) {
        let offset = sin(latitude) * sin(declination)
        let amplitude = cos(latitude) * cos(declination)
        let sineAltitude = offset + amplitude * cos(hourAngle)
        let altitude = asin(min(max(sineAltitude, -1), 1)) / radians
        let highestAltitude = asin(min(max(offset + amplitude, -1), 1)) / radians
        guard altitude >= 0, highestAltitude > 0 else { return (altitude, nil) }

        // Circumpolar bodies use the entire rotation when there is no horizon crossing.
        let limit = amplitude > 1e-12 ? acos(min(max(-offset / amplitude, -1), 1)) : .pi
        guard limit > 0 else { return (altitude, nil) }
        let signedHourAngle = atan2(sin(hourAngle), cos(hourAngle))
        let progress = min(max((signedHourAngle / limit + 1) / 2, 0), 1)
        return (altitude, TrackPoint(progress: progress, height: min(altitude / highestAltitude, 1)))
    }

    private static func daysSinceJ2000(_ date: Date) -> Double {
        // The Julian day at the Unix epoch is 2440587.5; J2000 is 2451545.
        date.timeIntervalSince1970 / 86_400 - 10_957.5
    }

    private static func solarPosition(days: Double) -> EquatorialPosition {
        let anomaly = (357.5291 + 0.98560028 * days) * radians
        let correction = (1.9148 * sin(anomaly) + 0.02 * sin(2 * anomaly) + 0.0003 * sin(3 * anomaly)) * radians
        let longitude = anomaly + correction + 102.9372 * radians + .pi
        return EquatorialPosition(longitude: longitude, latitude: 0)
    }

    private static func lunarPosition(days: Double) -> (position: EquatorialPosition, distance: Double) {
        let meanLongitude = (218.316 + 13.176396 * days) * radians
        let anomaly = (134.963 + 13.064993 * days) * radians
        let argumentOfLatitude = (93.272 + 13.229350 * days) * radians
        let position = EquatorialPosition(longitude: meanLongitude + 6.289 * radians * sin(anomaly),
                                          latitude: 5.128 * radians * sin(argumentOfLatitude))
        return (position, 385_001 - 20_905 * cos(anomaly))
    }

    private static func lunarPhase(sun: EquatorialPosition, moon: EquatorialPosition, moonDistance: Double) -> Moon {
        let sunDistance = 149_598_000.0
        let rightAscensionDifference = sun.rightAscension - moon.rightAscension
        let cosineElongation = sin(sun.declination) * sin(moon.declination)
            + cos(sun.declination) * cos(moon.declination) * cos(rightAscensionDifference)
        let elongation = acos(min(max(cosineElongation, -1), 1))
        let phaseAngle = atan2(sunDistance * sin(elongation), moonDistance - sunDistance * cos(elongation))
        let brightLimbAngle = atan2(cos(sun.declination) * sin(rightAscensionDifference),
                                    sin(sun.declination) * cos(moon.declination)
                                        - cos(sun.declination) * sin(moon.declination) * cos(rightAscensionDifference))
        return Moon(illumination: (1 + cos(phaseAngle)) / 2, isWaxing: brightLimbAngle < 0)
    }
}
