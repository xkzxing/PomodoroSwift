import Foundation

nonisolated struct LakeDaySchedule: Equatable {
    struct Activity: Equatable {
        let start: Date
        let end: Date

        func progress(at date: Date) -> Double? {
            guard date >= start, date < end else { return nil }
            return date.timeIntervalSince(start) / end.timeIntervalSince(start)
        }

        func intensity(at date: Date, fadeIn: TimeInterval, fadeOut: TimeInterval) -> Double {
            LakeDaySchedule.smooth(date.timeIntervalSince(start) / fadeIn)
                * LakeDaySchedule.smooth(end.timeIntervalSince(date) / fadeOut)
        }
    }

    struct Boat: Equatable {
        // Position on the same left-to-right route, including on the return trip.
        let position: Double
        let returning: Bool
        let opacity: Double
    }

    struct Motion: Equatable {
        let boat: Boat?
        let ducks: Double?
        let duckCount: Int
        let walker: Double?
        let lanternVisitor: Double?
        let porch: Double
    }

    let day: DateInterval
    let timeZone: TimeZone
    let outbound: Activity?
    let inbound: Activity?
    let ducks: Activity?
    let duckCount: Int
    let walker: Activity?
    let lanternVisitor: Activity?
    let windows: Activity
    let porch: Activity?

    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    init(at date: Date, calendar: Calendar = Self.localCalendar, demo: Bool = false) {
        let day = calendar.dateInterval(of: .day, for: date)!
        self.day = day
        timeZone = calendar.timeZone
        let civilDate = calendar.dateComponents([.year, .month, .day], from: date)
        let seed = UInt64(truncatingIfNeeded: (civilDate.year ?? 0) * 10_000
                          + (civilDate.month ?? 0) * 100 + (civilDate.day ?? 0))

        // Independent stable samples for each choice. Swift's Hasher changes on each launch.
        func sample(_ salt: UInt64, modulo: Int) -> Int {
            var bits = seed &+ (salt &* 0x9E3779B97F4A7C15)
            bits = (bits ^ (bits >> 30)) &* 0xBF58476D1CE4E5B9
            bits = (bits ^ (bits >> 27)) &* 0x94D049BB133111EB
            return Int((bits ^ (bits >> 31)) % UInt64(modulo))
        }

        func varies(_ maximum: Int, salt: UInt64) -> Int {
            demo ? 0 : sample(salt, modulo: maximum * 2 + 1) - maximum
        }

        func clock(_ minute: Int) -> Date {
            calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                          of: day.start, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
                ?? day.start.addingTimeInterval(TimeInterval(minute * 60))
        }

        func outing(_ minute: Int, lasting minutes: Int) -> Activity {
            let start = clock(minute)
            return Activity(start: start, end: min(day.end, start.addingTimeInterval(TimeInterval(minutes * 60))))
        }

        let boatDay = demo || sample(1, modulo: 100) < 80
        outbound = boatDay ? outing(9 * 60 + 15 + varies(29, salt: 2), lasting: 180) : nil
        inbound = boatDay ? outing(17 * 60 + 15 + varies(25, salt: 3), lasting: 180) : nil
        ducks = demo || sample(4, modulo: 100) < 75 ? outing(6 * 60 + 40 + varies(20, salt: 5), lasting: 60) : nil
        duckCount = demo ? 3 : 2 + sample(6, modulo: 2)
        walker = demo || sample(7, modulo: 100) < 60 ? outing(13 * 60 + 30 + varies(55, salt: 8), lasting: 18) : nil
        let visit = demo || sample(9, modulo: 100) < 25 ? outing(19 * 60 + 15 + varies(20, salt: 10), lasting: 16) : nil
        lanternVisitor = visit
        porch = visit.map {
            Activity(start: $0.end.addingTimeInterval(-60),
                     end: min(day.end, $0.end.addingTimeInterval(30 * 60)))
        }
        windows = Activity(start: clock(17 * 60), end: clock(22 * 60 + 45 + varies(15, salt: 11)))
    }

    func covers(_ date: Date, calendar: Calendar) -> Bool {
        day.start <= date && date < day.end && timeZone == calendar.timeZone
    }

    func motion(at date: Date) -> Motion {
        let boat: Boat?
        if let outbound, let progress = outbound.progress(at: date) {
            boat = Boat(position: progress, returning: false,
                        opacity: outbound.intensity(at: date, fadeIn: 150, fadeOut: 150))
        } else if let inbound, let progress = inbound.progress(at: date) {
            boat = Boat(position: 1 - progress, returning: true,
                        opacity: inbound.intensity(at: date, fadeIn: 150, fadeOut: 150))
        } else {
            boat = nil
        }
        return Motion(boat: boat, ducks: ducks?.progress(at: date), duckCount: duckCount,
                      walker: walker?.progress(at: date), lanternVisitor: lanternVisitor?.progress(at: date),
                      porch: porch?.intensity(at: date, fadeIn: 60, fadeOut: 60) ?? 0)
    }

    func windowLight(at date: Date) -> Double {
        windows.intensity(at: date, fadeIn: 300, fadeOut: 180)
    }

    static func detailVisibility(sunAltitude: Double) -> Double {
        smooth((sunAltitude + 6) / 6)
    }

    private static func smooth(_ fraction: Double) -> Double {
        let t = min(max(fraction, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
