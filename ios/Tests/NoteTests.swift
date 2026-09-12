import XCTest
@testable import SuishouCun

final class NoteTests: XCTestCase {
    func testSQLResponseAndWireRoundTrip() throws {
        let row: [String: Any] = ["id": "test-note", "title": "测试标题", "text": "第一行\n第二行", "pinned": "0", "sort_order": "7", "createdAt": "2026-09-08 08:30:00.000000", "updatedAt": "2026-09-12 12:00:01.000000"]
        let note = try Note.decode(row)
        XCTAssertFalse(note.pinned)
        XCTAssertEqual(note.sortOrder, 7)
        XCTAssertEqual(try Note.decode(note.wire), note)
    }
    func testNumericPinAndOrder() throws {
        let row: [String: Any] = ["id": "test-note", "title": "标题", "text": "正文", "pinned": 1, "sort_order": -2, "createdAt": "2026-09-08T08:30:00Z", "updatedAt": "2026-09-12T12:00:01Z"]
        let note = try Note.decode(row)
        XCTAssertTrue(note.pinned)
        XCTAssertEqual(note.sortOrder, -2)
    }
    func testRejectMalformedData() {
        XCTAssertThrowsError(try Note.decode(["id": "broken"]))
    }
}
