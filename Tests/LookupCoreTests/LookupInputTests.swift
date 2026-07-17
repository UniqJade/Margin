import XCTest
@testable import LookupCore

final class LookupInputTests: XCTestCase {
    func testNormalizerTrimsAndCollapsesWhitespace() throws {
        let normalized = try LookupInputNormalizer.normalize("  That  started\n an exchange.  ")

        XCTAssertEqual(normalized, "That started an exchange.")
    }

    func testNormalizerRejectsEmptySelection() {
        XCTAssertThrowsError(try LookupInputNormalizer.normalize(" \n\t ")) { error in
            XCTAssertEqual(error as? LookupInputError, .emptySelection)
        }
    }

    func testNormalizerRejectsMoreThanTwoThousandCharacters() {
        XCTAssertThrowsError(try LookupInputNormalizer.normalize(String(repeating: "a", count: 2_001))) { error in
            XCTAssertEqual(error as? LookupInputError, .selectionTooLong(limit: 2_000))
        }
    }

    func testClassifierRecognizesWordAndPassage() {
        XCTAssertEqual(LookupClassifier.classify("exchange"), .word)
        XCTAssertEqual(LookupClassifier.classify("an exchange"), .passage)
        XCTAssertEqual(LookupClassifier.classify("cyanide-laced"), .word)
    }
}
