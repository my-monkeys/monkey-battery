import Foundation

/// Time left, worded for where it is read.
///
/// Every value is rounded *down*: a battery that turns out to last a minute longer than
/// announced is a pleasant surprise, the opposite is the failure this app is for. The
/// precision also shrinks with distance — "25 min" when it is far off, seconds when they
/// are what is left.
public enum TimeLeft {
    /// At most six characters, for the menu bar: `1h05`, `25 min`, `4 min`, `1:45`.
    public static func short(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds))
        switch whole {
        case 3600...:
            return String(format: "%dh%02d", whole / 3600, whole % 3600 / 60)
        case 900...:
            return "\(whole / 60 / 5 * 5) min"
        case 120...:
            return "\(whole / 60) min"
        default:
            return clock(whole)
        }
    }

    /// For the popover headline: `1 h 05`, `≈ 25 min`, `4 min`, `1:45`.
    public static func long(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds))
        switch whole {
        case 3600...:
            return String(format: "%d h %02d", whole / 3600, whole % 3600 / 60)
        case 900...:
            return "≈ \(whole / 60 / 5 * 5) min"
        case 120...:
            return "\(whole / 60) min"
        default:
            return clock(whole)
        }
    }

    /// `m:ss`, for the last two minutes.
    public static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
