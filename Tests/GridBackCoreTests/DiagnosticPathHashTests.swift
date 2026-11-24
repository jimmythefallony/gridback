import XCTest
import GridBackCore

final class DiagnosticPathHashTests: XCTestCase {
    func testPathHashNeverOutputsThePath() {
        let paths = [
            "/Users/example/Downloads/photo.jpg",
            "/Users/example/Desktop/wallpaper.heic",
            "/Users/example/Documents/vacation.png",
            "/Users/example/Downloads/abcdef12",
            "/Users/example",
            "/Users/example/Downloads/photo.jpg|1718x1112|dark|still|0|0"
        ]
        for path in paths {
            let hashed = DiagnosticPathHash.text(for: path)
            let number = DiagnosticPathHash.number(for: path)
            let decimal = String(number)
            XCTAssertEqual(hashed.count, 8, path)
            XCTAssertTrue(hashed.allSatisfy(\.isHexDigit), hashed)
            XCTAssertEqual(hashed, DiagnosticPathHash.text(for: path))
            XCTAssertEqual(number, DiagnosticPathHash.number(for: path))
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
        }
        XCTAssertNotEqual(
            DiagnosticPathHash.text(for: "/Users/example/Downloads/photo.jpg"),
            DiagnosticPathHash.text(for: "/Users/example/Desktop/wallpaper.heic")
        )
        let empty = DiagnosticPathHash.text(for: "")
        XCTAssertEqual(empty.count, 8)
        XCTAssertFalse(empty.contains("/"))
    }
}
