import Foundation

/// Countdown logic for the break timer, independent of UI and wall clocks so
/// it can be unit tested by injecting `now`.
public final class BreakTimerModel {
    public private(set) var duration: TimeInterval
    private var startDate: Date
    public var showElapsedAfterExpiry: Bool

    public init(minutes: Int, showElapsedAfterExpiry: Bool = true, now: Date = Date()) {
        self.duration = TimeInterval(max(0, minutes)) * 60
        self.startDate = now
        self.showElapsedAfterExpiry = showElapsedAfterExpiry
    }

    /// Seconds remaining; negative once expired.
    public func remaining(now: Date = Date()) -> TimeInterval {
        duration - now.timeIntervalSince(startDate)
    }

    public func isExpired(now: Date = Date()) -> Bool {
        remaining(now: now) <= 0
    }

    /// Adjust the timer by whole minutes (Ctrl+scroll / arrow keys). Adjusting
    /// restarts the countdown from the new value, like ZoomIt.
    public func adjust(byMinutes delta: Int, now: Date = Date()) {
        let remainingNow = max(0, remaining(now: now))
        var newDuration = remainingNow + TimeInterval(delta * 60)
        // Round to whole minutes the way ZoomIt's arrow keys do.
        newDuration = (newDuration / 60).rounded(delta >= 0 ? .down : .up) * 60
        duration = max(60, newDuration)
        startDate = now
    }

    public func restart(now: Date = Date()) {
        startDate = now
    }

    /// "MM:SS" while counting down; "-MM:SS" elapsed after expiry.
    public func displayString(now: Date = Date()) -> String {
        let r = remaining(now: now)
        if r >= 0 {
            return Self.format(seconds: r)
        } else if showElapsedAfterExpiry {
            return "-" + Self.format(seconds: -r)
        } else {
            return Self.format(seconds: 0)
        }
    }

    public static func format(seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
