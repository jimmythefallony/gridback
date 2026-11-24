import XCTest
import GridBackCore

final class DiagnosticPathHashTests: XCTestCase {
    func testSameTextHasTheSameHashWithinALaunch() {
        let path = "/Users/example/Downloads/photo.jpg"
        XCTAssertEqual(DiagnosticPathHash.number(for: path), DiagnosticPathHash.number(for: path))
        XCTAssertEqual(DiagnosticPathHash.text(for: path), DiagnosticPathHash.text(for: path))
        let salt: UInt64 = 0xA1B2_C3D4_E5F6_0718
        XCTAssertEqual(
            DiagnosticPathHash.number(for: path, salt: salt),
            DiagnosticPathHash.number(for: path, salt: salt)
        )
        XCTAssertEqual(
            DiagnosticPathHash.text(for: path, salt: salt),
            DiagnosticPathHash.text(for: path, salt: salt)
        )
    }

    func testDifferentSaltsGiveDifferentHashes() {
        let path = "/Users/example/Downloads/photo.jpg"
        let first: UInt64 = 0x1111_2222_3333_4444
        let second: UInt64 = 0x5555_6666_7777_8888
        XCTAssertNotEqual(
            DiagnosticPathHash.number(for: path, salt: first),
            DiagnosticPathHash.number(for: path, salt: second)
        )
        XCTAssertNotEqual(
            DiagnosticPathHash.text(for: path, salt: first),
            DiagnosticPathHash.text(for: path, salt: second)
        )
    }

    func testOutputNeverContainsThePathOrTheSalt() {
        let paths = [
            "/Users/example/Downloads/photo.jpg",
            "/Users/example/Desktop/wallpaper.heic",
            "/Users/example/Documents/vacation.png",
            "/Users/example/Downloads/abcdef12",
            "/Users/example",
            "/Users/example/Downloads/photo.jpg|1718x1112|dark|still|0|0"
        ]
        let salts: [UInt64] = [
            0xA1B2_C3D4_E5F6_0718,
            0x1111_2222_3333_4444,
            0xFEDC_BA98_7654_3210
        ]
        for path in paths {
            assertDoesNotLeak(path, salt: nil)
            for salt in salts {
                assertDoesNotLeak(path, salt: salt)
            }
        }
        XCTAssertNotEqual(
            DiagnosticPathHash.text(for: "/Users/example/Downloads/photo.jpg"),
            DiagnosticPathHash.text(for: "/Users/example/Desktop/wallpaper.heic")
        )
        let empty = DiagnosticPathHash.text(for: "")
        XCTAssertEqual(empty.count, 8)
        XCTAssertFalse(empty.contains("/"))
    }

    private func assertDoesNotLeak(_ path: String, salt: UInt64?) {
        let hashed: String
        let number: UInt32
        if let salt {
            hashed = DiagnosticPathHash.text(for: path, salt: salt)
            number = DiagnosticPathHash.number(for: path, salt: salt)
        } else {
            hashed = DiagnosticPathHash.text(for: path)
            number = DiagnosticPathHash.number(for: path)
        }
        let decimal = String(number)
        XCTAssertEqual(hashed.count, 8, path)
        XCTAssertTrue(hashed.allSatisfy(\.isHexDigit), hashed)
        XCTAssertFalse(hashed.contains(path), hashed)
        XCTAssertFalse(hashed.contains("/"), hashed)
        XCTAssertFalse(hashed.contains("\\"), hashed)
        XCTAssertFalse(hashed.contains("."), hashed)
        XCTAssertFalse(hashed.contains("example"), hashed)
        XCTAssertFalse(hashed.contains("Users"), hashed)
        XCTAssertFalse(hashed.contains("Downloads"), hashed)
        XCTAssertFalse(hashed.contains("Desktop"), hashed)
        XCTAssertFalse(hashed.contains("Documents"), hashed)
        XCTAssertFalse(hashed.contains("photo"), hashed)
        XCTAssertFalse(hashed.contains("wallpaper"), hashed)
        XCTAssertFalse(hashed.contains("vacation"), hashed)
        XCTAssertFalse(hashed.contains("abcdef12"), hashed)
        XCTAssertNotEqual(hashed, path)
        XCTAssertFalse(decimal.contains(path), decimal)
        XCTAssertFalse(decimal.contains("/"), decimal)
        XCTAssertFalse(decimal.contains("example"), decimal)
        XCTAssertNotEqual(decimal, path)
        if let salt {
            let saltDecimal = String(salt)
            let saltHex = String(salt, radix: 16, uppercase: false)
            XCTAssertFalse(hashed.contains(saltDecimal), hashed)
            XCTAssertFalse(hashed.contains(saltHex), hashed)
            XCTAssertFalse(decimal.contains(saltDecimal), decimal)
            XCTAssertFalse(decimal.contains(saltHex), decimal)
            XCTAssertNotEqual(hashed, saltHex)
            XCTAssertNotEqual(decimal, saltDecimal)
        }
    }
}
