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
/// `RunMeta`'s existing scope).
///
/// ## Two fingerprints, two different guarantees — do not conflate them
///
/// `compute(_:)` and `computeExact(_:)` below serve different purposes and
/// are stored as two separate `ParagraphMeta` fields
/// (`textFingerprint` / `exactTextFingerprint`):
///
/// - `compute(_:)` ("loose") tolerates markdown-round-trip noise
///   (whitespace collapsing, typographic canonicalization) — appropriate
///   for "is this still roughly the same paragraph" misalignment detection
///   (macdoc #220 item 5), which gates paragraph-*level* fields
///   (alignment/spacing/etc. — none of which depend on character offsets).
/// - `computeExact(_:)` requires byte-for-byte identical text — this is
///   the ONLY fingerprint that guarantees `RunMeta.range` character offsets
///   are still valid, because the loose fingerprint's normalization steps
///   are length-changing and can silently shift or invalidate offsets even
///   when it matches. Per-run restoration (macdoc #220 item 4) MUST gate on
///   `computeExact`, not `compute`. See `computeExact`'s own doc comment
///   for a concrete worked example of why the loose fingerprint is unsafe
///   for this.
///
/// ## Normalization (applies to `compute(_:)` only — `computeExact(_:)`
/// ## applies none of it)
///
/// 1. Unicode NFC normalize (`precomposedStringWithCanonicalMapping`).
/// 2. **Typographic canonicalization**: fold "smart punctuation" variants
///    down to their plain-ASCII equivalents — curly single/double quotes to
///    `'`/`"`, en dash (U+2013) to `--`, em dash (U+2014) to `---`,
///    horizontal ellipsis (U+2026) to `...`. See rationale below.
/// 3. Collapse every run of Unicode whitespace/newline characters to a
///    single ASCII space.
/// 4. Trim leading/trailing whitespace.
/// 5. Hash the normalized text with FNV-1a (64-bit), rendered as 16
///    lowercase hex digits.
///
/// ## Why normalize at all — what markdown round-tripping changes, and
/// what it does not
///
/// - **Markdown escaping (backslash before `*_` etc.) is not a source of
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
/// - **Whitespace differences are real and absorbed by steps 3-4**:
///   multiple interior spaces, trailing whitespace, or a hard line break's
///   trailing two spaces can all shift slightly across a markdown
///   round-trip without the paragraph's actual content having changed.
/// - **Smart punctuation is real and absorbed by step 2 — discovered
///   empirically, not theoretically.** swift-markdown's `Document(parsing:)`
///   enables cmark's "smart" option set by default (no `.disableSmartOpts`
///   passed anywhere in `md-to-word-swift`): parsing markdown source
///   containing a literal straight apostrophe/quote, or an ASCII `--` /
///   `---` / `...` sequence, silently rewrites it to the corresponding
///   Unicode typographic character — verified by round-tripping
///   `"This paragraph's real text."` through
///   `MarkdownToWordConverter.convertMarkdown` and observing the straight
///   `'` come back as U+2019 (curly right single quote). Since apostrophes
///   and straight quotes are near-ubiquitous in ordinary prose, leaving
///   this unhandled would make the fingerprint mismatch on nearly every
///   real paragraph containing a contraction or possessive — a
///   false-positive rate that would defeat the feature's purpose. Folding
///   both the ASCII and the Unicode typographic form down to the same
///   canonical ASCII representation makes the fingerprint correctly match
///   across that specific, deterministic parser behavior.
/// - **Residual, documented gap**: this canonicalization is intentionally
///   lossy — a paragraph that genuinely started with a literal Unicode em
///   dash will now fingerprint identically to one that started with literal
///   `---`. That is an accepted trade-off (misalignment detection needs to
///   tolerate this one parser behavior; distinguishing those two literal
///   inputs is not a goal). Other smart-punctuation-adjacent substitutions
///   cmark may perform in less common contexts are not separately
///   inventoried here; if a future false-mismatch is traced to one, extend
///   this list (and the matching macdoc copy + shared test vectors)
///   accordingly rather than special-casing it ad hoc.
/// - **An actual content edit (insertion, deletion, or replacement of
///   non-whitespace, non-typographic text) always changes the fingerprint.**
///   This is a content-drift detector, not a byte-exact round-trip
///   checksum: it is deliberately insensitive to the noise above while
///   staying sensitive to any edit a human or tool made to the paragraph's
///   actual wording.
///
/// ## Hash collisions (Codex round 2 NEW-3)
///
/// FNV-1a 64-bit is not a cryptographic hash and is not injective: two
/// different texts could, in principle, hash to the same digest. A match on
/// either `compute(_:)` or `computeExact(_:)` is therefore strong practical
/// evidence of equality (over the relevant text universe, a 64-bit digest
/// makes an accidental collision astronomically unlikely), not a
/// mathematical proof. This is an acceptable trade-off for a
/// misalignment/offset-safety check — not a security boundary — but the
/// doc comments elsewhere in this file that say a match "guarantees"
/// equality should be read with this caveat in mind rather than taken
/// literally.
enum ParagraphFingerprint {
    /// Unicode "smart punctuation" scalar → canonical ASCII replacement.
    /// See the "Smart punctuation" bullet above for why this exists.
    private static let typographicCanonicalization: [Unicode.Scalar: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'", // single quote family
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"", // double quote family
        "\u{2013}": "--",   // en dash
        "\u{2014}": "---",  // em dash
        "\u{2026}": "...",  // horizontal ellipsis
    ]

    /// Computes the "loose" fingerprint for a paragraph's already-concatenated
    /// run text (callers pass `paragraph.runs.map(\.text).joined()`). Tolerant
    /// of the whitespace-collapsing and typographic-canonicalization noise
    /// described above — appropriate for "is this roughly the same paragraph"
    /// misalignment detection, NOT sufficient on its own for validating that
    /// `RunMeta.range` character offsets are still safe to apply (see
    /// `computeExact` below).
    static func compute(_ runsText: String) -> String {
        fnv1a64Hex(normalize(runsText))
    }

    /// Computes the "exact" fingerprint: hashes `runsText` with NO
    /// normalization at all (not NFC, not whitespace collapsing, not
    /// typographic canonicalization) — a match is strong (FNV-1a 64-bit,
    /// practically collision-free for this use case) but not
    /// mathematically-proof evidence the two texts are scalar-for-scalar
    /// identical, the same caveat any fixed-width non-cryptographic hash
    /// carries (see the top-level doc comment's "Hash collisions" note).
    ///
    /// This is the fingerprint `RunMeta.range` scalar-offset restoration
    /// (macdoc #220 item 4) must gate on, NOT `compute(_:)` above. Both
    /// whitespace collapsing and typographic canonicalization are
    /// *length-changing* transformations (e.g. `"  "` → `" "`, or `"---"`
    /// (3 chars) ↔ `"—"` (1 char)): two texts can normalize to the same
    /// "loose" fingerprint while having different lengths or different
    /// character positions, which silently invalidates — or worse, shifts —
    /// offsets captured against the *other* text. Concretely: original text
    /// `"a---bc"` with a `RunMeta.range` of `[4, 5)` (targeting `"b"`)
    /// round-trips through markdown to `"a—bc"` (smart-punctuation
    /// substitution, unrelated to any real edit); the *loose* fingerprint of
    /// both strings is identical, but `[4, 5)` against `"a—bc"` is out of
    /// bounds (length 4) — or, with more trailing text, could land on a
    /// *different* character than `"b"` entirely, silently formatting the
    /// wrong text. `computeExact` closes that gap: a match means the
    /// offsets are (for all practical purposes) still valid.
    static func computeExact(_ runsText: String) -> String {
        fnv1a64Hex(runsText)
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
            if let replacement = typographicCanonicalization[scalar] {
                result += replacement
                lastWasWhitespace = false
                continue
            }
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
