import XCTest
@testable import ZoomItCore

final class BreakTimerModelTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)

    func testCountdown() {
        let timer = BreakTimerModel(minutes: 10, now: start)
        XCTAssertEqual(timer.remaining(now: start), 600, accuracy: 0.001)
        let later = start.addingTimeInterval(90)
        XCTAssertEqual(timer.remaining(now: later), 510, accuracy: 0.001)
        XCTAssertFalse(timer.isExpired(now: later))
    }

    func testExpiryAndElapsed() {
        let timer = BreakTimerModel(minutes: 1, showElapsedAfterExpiry: true, now: start)
        let after = start.addingTimeInterval(90)
        XCTAssertTrue(timer.isExpired(now: after))
        XCTAssertEqual(timer.displayString(now: after), "-0:30")
    }

    func testExpiredWithoutElapsedShowsZero() {
        let timer = BreakTimerModel(minutes: 1, showElapsedAfterExpiry: false, now: start)
        let after = start.addingTimeInterval(120)
        XCTAssertEqual(timer.displayString(now: after), "0:00")
    }

    func testAdjustUpAddsMinuteAndRestarts() {
        let timer = BreakTimerModel(minutes: 5, now: start)
        let mid = start.addingTimeInterval(30) // 4:30 remaining
        timer.adjust(byMinutes: 1, now: mid)
        // 4:30 + 1:00 = 5:30, rounded down to 5:00
        XCTAssertEqual(timer.remaining(now: mid), 300, accuracy: 0.001)
    }

    func testAdjustDownNeverGoesBelowOneMinute() {
        let timer = BreakTimerModel(minutes: 1, now: start)
        timer.adjust(byMinutes: -5, now: start)
        XCTAssertEqual(timer.remaining(now: start), 60, accuracy: 0.001)
    }

    func testDisplayFormats() {
        XCTAssertEqual(BreakTimerModel.format(seconds: 0), "0:00")
        XCTAssertEqual(BreakTimerModel.format(seconds: 59), "0:59")
        XCTAssertEqual(BreakTimerModel.format(seconds: 600), "10:00")
        XCTAssertEqual(BreakTimerModel.format(seconds: 3725), "1:02:05")
    }
}
