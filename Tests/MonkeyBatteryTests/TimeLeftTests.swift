import Foundation
import MonkeyBatteryCore
import Testing

@Suite("Time left wording")
struct TimeLeftTests {
    @Test("menu bar: always rounded down, never wider than six characters", arguments: [
        (TimeInterval(3959), "1h05"),
        (3600, "1h00"),
        (1799, "25 min"),
        (900, "15 min"),
        (899, "14 min"),
        (120, "2 min"),
        (119, "1:59"),
        (9, "0:09"),
        (-4, "0:00"),
    ])
    func short(seconds: TimeInterval, expected: String) {
        #expect(TimeLeft.short(seconds) == expected)
        #expect(TimeLeft.short(seconds).count <= 6)
    }

    @Test("popover: the coarse range says it is approximate")
    func long() {
        #expect(TimeLeft.long(1799) == "≈ 25 min")
        #expect(TimeLeft.long(3959) == "1 h 05")
        #expect(TimeLeft.long(299) == "4 min")
        #expect(TimeLeft.long(61) == "1:01")
    }

    @Test("a range shares its unit when it can, and rounds both ends down")
    func range() {
        #expect(TimeLeft.range(12 * 60 + 59, 25 * 60 + 30) == "12 – 25 min")
        #expect(TimeLeft.range(50 * 60, 3 * 3600 + 5 * 60 + 59) == "50 min – 3 h 05")
        #expect(TimeLeft.range(70 * 60, 3 * 3600) == "1 h 10 – 3 h 00")
    }
}
