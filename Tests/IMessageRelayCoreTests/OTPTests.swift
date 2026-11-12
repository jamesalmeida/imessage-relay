import XCTest
@testable import IMessageRelayCore

final class OTPTests: XCTestCase {
    func testTypicalOneTimeCodesAreDetected() {
        let samples = [
            "Your Apple ID code is 123456. Don't share it with anyone.",
            "Your Apple ID Code is: 123456. Don't share it with anyone.",
            "G-493821 is your Google verification code.",
            "Use code G-493821 to continue",
            "Chase: Your one-time security code is 847291. Do not share this code.",
            "Your Uber code is 4921",
            "YOUR VERIFICATION CODE IS 445566",
            "OTP 102938",
            "Your passcode is 445566",
            "2FA authentication code: 019283",
            "123456 is your sign-in code",
            "Please confirm 123456",
            "Your code is 1234",
            "Your code is 12345678",
            "123456 Don\u{2019}t share this with anyone",
        ]
        for sample in samples {
            XCTAssertTrue(OTPDetector.isOneTimeCode(sample), sample)
        }
    }

    func testOrdinaryNumbersAreNotSkipped() {
        let samples = [
            "Meet me at 1234 Market Street tomorrow",
            "The total is $1,234.56 for 3 items",
            "Dinner is at 7:30, party of 12",
            "Call me at (415) 555-0100 tomorrow",
            "Call me at (415) 555-0100 to verify delivery",
            "Please verify the office at 1234 Market Street",
            "Please verify the charge of $1234 today",
            "Please verify arrival at 12:30",
            "The postcode is 94107",
            "barcode 12345678",
            "Your confirmation number is 12345678",
            "Your code is 123",
            "Your code is 123456789",
            "G-493821",
            "Order 48219375 ships Friday",
            "See you in 15 minutes at room 12",
            "The garage code is here." + String(repeating: "x", count: 120) + "Bring 4500 tiles.",
            "Do not share this photo",
        ]
        for sample in samples {
            XCTAssertFalse(OTPDetector.isOneTimeCode(sample), sample)
        }
    }

    func testDatabaseFlags() {
        XCTAssertTrue(OTPDetector.isIndicatorColumn("is_otp"))
        XCTAssertTrue(OTPDetector.isIndicatorColumn("otp_code"))
        XCTAssertTrue(OTPDetector.isIndicatorColumn("one_time_code"))
        XCTAssertTrue(OTPDetector.isIndicatorColumn("verification_code"))
        XCTAssertFalse(OTPDetector.isIndicatorColumn("is_spam"))
        XCTAssertFalse(OTPDetector.isIndicatorColumn("schedule_type"))
        XCTAssertFalse(OTPDetector.isIndicatorColumn("schedule_state"))
        XCTAssertFalse(OTPDetector.isIndicatorColumn("is_auto_reply"))
        XCTAssertFalse(OTPDetector.isIndicatorColumn("expressive_send_style_id"))
        XCTAssertFalse(OTPDetector.isIndicatorColumn("not_otp"))
    }

    func testSkipToggleAndFlag() {
        XCTAssertFalse(shouldSkipOneTimeCode(text: "Your code is 123456", otpFlagged: true, enabled: false))
        XCTAssertTrue(shouldSkipOneTimeCode(text: "hello", otpFlagged: true, enabled: true))
        XCTAssertFalse(shouldSkipOneTimeCode(text: "hello", otpFlagged: false, enabled: true))
        XCTAssertFalse(shouldSkipOneTimeCode(text: nil, otpFlagged: false, enabled: true))
        XCTAssertTrue(shouldSkipOneTimeCode(text: "Your Uber code is 4921", otpFlagged: false, enabled: true))
    }
}
