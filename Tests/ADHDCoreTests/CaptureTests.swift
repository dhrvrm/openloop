import Foundation
import Testing
@testable import ADHDCore

@Test func captureTrimsOuterWhitespaceWithoutChangingMeaning() throws {
    let capture = try RawCapture(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        createdAt: Date(timeIntervalSince1970: 10),
        text: "  Send Riya the revised flow  "
    )

    #expect(capture.text == "Send Riya the revised flow")
}

@Test func emptyCaptureIsRejected() {
    #expect(throws: CaptureError.emptyText) {
        try RawCapture(createdAt: .now, text: " \n ")
    }
}
