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

    // MARK: - Typographic canonicalization (swift-markdown's default "smart
    // punctuation" — see ParagraphFingerprint's doc comment)

    func testFingerprintCanonicalizesApostrophe() {
        XCTAssertEqual(ParagraphFingerprint.compute("This paragraph's real text."), "dea38bc387d1a018")
    }

    func testFingerprintOfCurlyApostropheMatchesStraightApostrophe() {
        // U+2019 RIGHT SINGLE QUOTATION MARK — what swift-markdown produces
        // when it re-parses a straight apostrophe under its default "smart"
        // option set.
        XCTAssertEqual(
            ParagraphFingerprint.compute("This paragraph\u{2019}s real text."),
            "dea38bc387d1a018"
        )
    }

    func testFingerprintCanonicalizesDashesAndEllipsisAndDoubleQuotes() {
        XCTAssertEqual(
            ParagraphFingerprint.compute("He said \"hello\" -- then left..."),
            "a00291c1039d1aab"
        )
    }

    func testFingerprintOfFullyTypographicVariantMatchesASCIIVariant() {
        // U+201C/U+201D curly double quotes, U+2013 en dash, U+2026 ellipsis
        // — exactly what swift-markdown produces from the ASCII sequence
        // above under its default "smart" option set.
        XCTAssertEqual(
            ParagraphFingerprint.compute("He said \u{201C}hello\u{201D} \u{2013} then left\u{2026}"),
            "a00291c1039d1aab"
        )
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

    // MARK: - computeExact: byte-exact, NO normalization at all
    // (the fix for the offset-safety gap a Codex review round 1 finding
    // identified in `compute(_:)` — see ParagraphFingerprint's doc comment)

    func testComputeExactSharedLiteralVectors() {
        XCTAssertEqual(ParagraphFingerprint.computeExact("Hello, world!"), "38d1334144987bf4")
        XCTAssertEqual(ParagraphFingerprint.computeExact("This paragraph's real text."), "dea38bc387d1a018")
        XCTAssertEqual(ParagraphFingerprint.computeExact("A  B"), "96396e8c37aad7ca")
        XCTAssertEqual(ParagraphFingerprint.computeExact("A B"), "fa95d919a0cae6d2")
        XCTAssertEqual(ParagraphFingerprint.computeExact("a---bc"), "733503084b18a8c2")
        XCTAssertEqual(ParagraphFingerprint.computeExact("a\u{2014}bc"), "ba79b701407cd4b5")
        XCTAssertEqual(ParagraphFingerprint.computeExact(""), "cbf29ce484222325")
    }

    func testComputeExactDoesNotToleratesWhitespaceDifferences() {
        // Unlike compute(_:), computeExact(_:) must NOT collapse whitespace —
        // "A  B" and "A B" have different lengths, so offsets captured
        // against one are not valid against the other.
        XCTAssertNotEqual(
            ParagraphFingerprint.computeExact("A  B"),
            ParagraphFingerprint.computeExact("A B")
        )
        // Sanity: the loose fingerprint DOES still consider them equal —
        // pins the documented divergence between the two functions.
        XCTAssertEqual(
            ParagraphFingerprint.compute("A  B"),
            ParagraphFingerprint.compute("A B")
        )
    }

    func testComputeExactDoesNotToleratesTypographicSubstitution() {
        // Unlike compute(_:), computeExact(_:) must NOT canonicalize smart
        // punctuation — "a---bc" (6 chars) and "a—bc" (4 chars, em dash)
        // have different lengths, so a RunMeta.range offset valid against
        // one is not necessarily valid (or could land on different text)
        // against the other.
        XCTAssertNotEqual(
            ParagraphFingerprint.computeExact("a---bc"),
            ParagraphFingerprint.computeExact("a\u{2014}bc")
        )
        XCTAssertEqual(
            ParagraphFingerprint.compute("a---bc"),
            ParagraphFingerprint.compute("a\u{2014}bc")
        )
    }

    func testComputeExactMatchesForByteIdenticalText() {
        let text = "Byte-identical text, unchanged."
        XCTAssertEqual(ParagraphFingerprint.computeExact(text), ParagraphFingerprint.computeExact(text))
    }
}
