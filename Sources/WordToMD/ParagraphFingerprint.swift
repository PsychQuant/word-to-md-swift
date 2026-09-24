import Foundation

/// Deterministic, cross-process-stable content fingerprint of a paragraph's
/// visible run text — written into the Tier 3 metadata sidecar
/// (`ParagraphMeta.textFingerprint`) so the reverse converter
/// (`md-to-word-swift`'s `Tier3MetadataRestorer`, in the macdoc repo) can
/// detect when a `ParagraphMeta.index` no longer points at the paragraph it
/// was captured against — e.g. because the markdown was hand-edited and a
/// paragraph was inserted earlier in the document, shifting every later
/// paragraph's index. See PsychQuant/macdoc#220 item 5.
///
/// ## Contract with macdoc's mirror copy (CRITICAL — keep both in sync)
///
/// macdoc's `packages/md-to-word-swift/Sources/MDToWord/ParagraphFingerprint.swift`
/// carries an independent, hand-duplicated copy of this exact algorithm (the
/// two packages are separate Swift modules in separate repos with no shared
/// dependency to host a common implementation in). Both files' test suites
/// pin the SAME literal hex digests as expected values for the SAME input
/// strings — `ParagraphFingerprintTests.swift` in this repo, and its mirror
/// in macdoc's `MDToWordTests`. If you change the normalization rule or the
/// hash algorithm here, you MUST make the identical change on the macdoc
/// side and update both sets of literal test vectors together, or a
/// fingerprint written by this package will never match one recomputed by
/// the reverse converter — silently defeating the whole feature (every
/// restoration would look like a mismatch).
///
/// ## What text goes into the fingerprint
///
/// The concatenation of `paragraph.runs.map(\.text)`, in run order — the
/// *same* text `MetadataCollector.collectParagraph` already walks to
/// compute `RunMeta.range` character offsets (top-level runs only;
/// hyperlink / footnote / SDT text is deliberately excluded, matching
/// `RunMeta`'s existing scope). This means a fingerprint match also
/// guarantees `RunMeta.range` offsets are valid against the corresponding
/// reverse-converted paragraph's own `runs`-only text — the per-run
/// restoration (macdoc #220 item 4) depends on this alignment.
///
/// ## Normalization
///
/// 1. Unicode NFC normalize (`precomposedStringWithCanonicalMapping`).
/// 2. Collapse every run of Unicode whitespace/newline characters to a
///    single ASCII space.
/// 3. Trim leading/trailing whitespace.
/// 4. Hash the normalized text with FNV-1a (64-bit), rendered as 16
///    lowercase hex digits.
///
/// ## Why normalize at all — what markdown round-tripping changes, and
/// what it does not
///
/// - **Markdown escaping (`\*`, `\_`, `` \` ``, …) is not a source of
///   difference here.** `WordConverter` escapes special characters only
///   when *serializing* a run's text into the `.md` file
///   (`MarkdownEscaping`, in the `markdown-swift` package); the reverse
///   side's markdown parser (`swift-markdown`) unescapes those sequences
///   back to the literal character when it re-parses `Text` nodes. Both
///   sides of this fingerprint operate on already-unescaped `Run.text` —
///   this package computes it directly from the original `WordDocument`
///   (before any markdown serialization happens at all), and the reverse
///   converter computes it from `Run.text` *after* swift-markdown has
///   already unescaped it. So escaping/unescaping is invisible to the
///   fingerprint by construction, not because normalization absorbs it.
/// - **Whitespace *is* a real, documented source of difference**, which is
///   exactly what steps 2-3 above absorb: multiple interior spaces,
///   trailing whitespace, or a hard line break's trailing two spaces can
///   all shift slightly across a markdown round-trip without the paragraph's
///   actual content having changed. Collapsing whitespace keeps those
///   incidental differences from registering as a false mismatch.
/// - **An actual content edit (insertion, deletion, or replacement of
///   non-whitespace text) always changes the fingerprint.** This is a
///   content-drift detector, not a byte-exact round-trip checksum: it is
///   deliberately insensitive to the whitespace noise above while staying
///   sensitive to any edit a human or tool made to the paragraph's text.
enum ParagraphFingerprint {
    /// Computes the fingerprint for a paragraph's already-concatenated run
    /// text (callers pass `paragraph.runs.map(\.text).joined()`).
    static func compute(_ runsText: String) -> String {
        fnv1a64Hex(normalize(runsText))
    }

    /// Exposed for the two-repo shared literal-test-vector contract
    /// described above — both `ParagraphFingerprintTests.swift` copies
    /// assert against `normalize(...)`'s output as well as `compute(...)`'s.
    static func normalize(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        var result = ""
        result.reserveCapacity(nfc.count)
        var lastWasWhitespace = false
        for scalar in nfc.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasWhitespace {
                    result.unicodeScalars.append(" ")
                }
                lastWasWhitespace = true
            } else {
                result.unicodeScalars.append(scalar)
                lastWasWhitespace = false
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// FNV-1a 64-bit — chosen over a cryptographic hash because this is a
    /// content-drift equality check, not a security boundary: no import
    /// beyond Foundation, fully deterministic across processes/platforms
    /// (unlike Swift's `Hasher`, which is per-process-salted and unsuitable
    /// for a value written to a durable file and read back elsewhere).
    private static func fnv1a64Hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }
}
