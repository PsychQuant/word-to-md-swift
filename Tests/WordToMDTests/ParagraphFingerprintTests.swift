import XCTest
@testable import WordToMD

/// Characterization tests for `ParagraphFingerprint` (PsychQuant/macdoc#220
/// item 5). These literal expected hex digests are the shared contract with
/// macdoc's independent mirror copy
/// (`packages/md-to-word-swift/Sources/MDToWord/ParagraphFingerprint.swift`,
/// whose test suite pins the identical vectors). If this test file's
/// expectations ever need to change, the macdoc-side copy of both the
/// algorithm and its test vectors must change identically in the same PR
/// cycle — see the doc comment on `ParagraphFingerprint` for why.
final class ParagraphFingerprintTests: XCTestCase {

    // MARK: - Shared literal test vectors (cross-repo contract)

    func testFingerprintOfPlainASCIIText() {
        XCTAssertEqual(ParagraphFingerprint.compute("Hello, world!"), "38d1334144987bf4")
    }

    func testFingerprintCollapsesInteriorWhitespace() {
        // Two interior double-spaces collapse to single spaces before hashing.
        XCTAssertEqual(ParagraphFingerprint.compute("café  naïve   text"), "f3e75da59db3cbf4")
    }

    func testFingerprintTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(ParagraphFingerprint.compute("  leading and trailing space  "), "4fd2d393b0def7d6")
    }

    func testFingerprintCollapsesNewlinesAndTabs() {
        XCTAssertEqual(ParagraphFingerprint.compute("line1\nline2\ttabbed"), "fa9bc3e805bb5524")
    }

    func testFingerprintOfEmptyString() {
        XCTAssertEqual(ParagraphFingerprint.compute(""), "cbf29ce484222325")
    }

    func testFingerprintOfSingleWord() {
        XCTAssertEqual(ParagraphFingerprint.compute("important"), "4f2844fb7985d8e5")
    }

    // MARK: - Content-drift sensitivity (the actual purpose of the feature)

    func testDifferentTextProducesDifferentFingerprint() {
        XCTAssertNotEqual(
            ParagraphFingerprint.compute("First paragraph."),
            ParagraphFingerprint.compute("Second paragraph.")
        )
    }

    func testSameTextProducesSameFingerprintDeterministically() {
        let text = "Repeat this exact sentence."
        XCTAssertEqual(ParagraphFingerprint.compute(text), ParagraphFingerprint.compute(text))
    }

    func testInsertedWordChangesFingerprint() {
        // The scenario item 5 exists to catch: a paragraph inserted earlier
        // in the document must not look identical to the original text at
        // the same index.
        XCTAssertNotEqual(
            ParagraphFingerprint.compute("The quick fox jumps."),
            ParagraphFingerprint.compute("The quick brown fox jumps.")
        )
    }

    // MARK: - Whitespace-only edits do NOT change the fingerprint

    func testWhitespaceOnlyDifferenceProducesSameFingerprint() {
        XCTAssertEqual(
            ParagraphFingerprint.compute("Same   content"),
            ParagraphFingerprint.compute("Same content")
        )
        XCTAssertEqual(
            ParagraphFingerprint.compute("Trailing space "),
            ParagraphFingerprint.compute("Trailing space")
        )
    }
}
