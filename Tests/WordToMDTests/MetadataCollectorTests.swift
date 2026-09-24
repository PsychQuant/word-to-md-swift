import XCTest
import CommonConverterSwift
import OOXMLSwift
@testable import WordToMD

final class MetadataCollectorTests: XCTestCase {

    // MARK: - Helpers

    private func makeYAML(from collector: MetadataCollector) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("test.meta.yaml")
        try collector.writeYAML(to: url)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - RunMeta.range is scalar-based, not Character-based
    // (PsychQuant/macdoc#220 item 4 follow-up, Codex round 2 NEW-1)

    func testRunMetaRangeIsMeasuredInUnicodeScalarsNotCharacters() throws {
        // A base letter and a combining acute accent, split across two
        // separately-formatted runs — each is its own single `Character`
        // when counted in isolation (`"a".count == 1`,
        // `"\u{0301}".count == 1`), so a naive per-run `Character`-count sum
        // would place "bc" at offset 2. If instead measured in Unicode
        // scalars (also 1 + 1 here), the offset is the same in THIS
        // fixture — the divergence only shows up once something reads
        // these offsets back against a *recombined* string (see the
        // reverse-side Tier3MetadataRestorer test in macdoc for the
        // scenario where that recombination actually changes the
        // Character-based count). This test instead pins the forward-side
        // contract directly: scalar count, asserted via an example where
        // `Character` count and `unicodeScalars` count of a SINGLE run
        // already disagree, so the two coordinate systems are
        // distinguishable within this one test.
        var collector = MetadataCollector()

        var doc = WordDocument()
        var boldProps = RunProperties(bold: true)
        boldProps.fontName = "Arial"
        // "é" as a single precomposed Character, but the run's underlying
        // Swift String can still be inspected at the scalar level: a
        // precomposed "é" (U+00E9) is ALSO exactly 1 scalar, so use a
        // decomposed sequence instead ("e" + COMBINING ACUTE ACCENT,
        // U+0065 U+0301) — 1 Character (grapheme cluster), but 2 scalars.
        let decomposedE = "e\u{0301}"
        XCTAssertEqual(decomposedE.count, 1, "Fixture assumption: base+combining-mark forms ONE Character")
        XCTAssertEqual(decomposedE.unicodeScalars.count, 2, "Fixture assumption: base+combining-mark is TWO scalars")

        let run1 = Run(text: decomposedE, properties: boldProps)
        let colorProps = RunProperties(color: "FF0000")
        let run2 = Run(text: "xyz", properties: colorProps)
        doc.appendParagraph(Paragraph(runs: [run1, run2]))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        // If range were Character-count-based, run1 (1 Character) would end
        // at offset 1, placing run2 at [1, 4). Scalar-count-based, run1 (2
        // scalars) ends at offset 2, placing run2 at [2, 5).
        XCTAssertTrue(yaml.contains("range: [0, 2]"), "run1 (decomposed é) should span scalar offsets [0, 2); got:\n\(yaml)")
        XCTAssertTrue(yaml.contains("range: [2, 5]"), "run2 (\"xyz\") should start at scalar offset 2, not Character offset 1; got:\n\(yaml)")
    }

    // MARK: - Bug Fix: characterSpacing

    func testCharacterSpacingIsWrittenToYAML() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = RunProperties()
        props.characterSpacing = CharacterSpacing(spacing: 20)
        let run = Run(text: "spaced", properties: props)
        doc.appendParagraph(Paragraph(runs: [run]))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("characterSpacing"), "characterSpacing should appear in YAML output")
        XCTAssertTrue(yaml.contains("spacing: 20"))
    }

    func testCharacterSpacingWithPositionAndKern() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = RunProperties()
        props.characterSpacing = CharacterSpacing(spacing: 10, position: 5, kern: 16)
        let run = Run(text: "text", properties: props)
        doc.appendParagraph(Paragraph(runs: [run]))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("spacing: 10"))
        XCTAssertTrue(yaml.contains("position: 5"))
        XCTAssertTrue(yaml.contains("kern: 16"))
    }

    // MARK: - Table Metadata

    func testTableMetadataCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var tableProps = TableProperties()
        tableProps.width = 9000
        tableProps.widthType = .dxa
        tableProps.alignment = .center
        let table = Table(rows: [
            TableRow(cells: [TableCell(text: "A")])
        ], properties: tableProps)
        doc.body.children = [.table(table)]
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("tables:"))
        XCTAssertTrue(yaml.contains("width: 9000"))
        XCTAssertTrue(yaml.contains("alignment: center"))
    }

    func testTableHeaderRowMetadata() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var headerRowProps = TableRowProperties()
        headerRowProps.isHeader = true
        var tableProps = TableProperties()
        tableProps.width = 9000
        let table = Table(rows: [
            TableRow(cells: [TableCell(text: "Header")], properties: headerRowProps),
            TableRow(cells: [TableCell(text: "Data")])
        ], properties: tableProps)
        doc.body.children = [.table(table)]
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("isHeader: true"))
    }

    // MARK: - Comment Content

    func testCommentContentCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        let comment = Comment(id: 1, author: "Alice", text: "Review this", paragraphIndex: 0)
        doc.comments.addComment(comment)
        doc.appendParagraph(Paragraph(text: "Text"))
        collector.collectDocument(doc)

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("comments:"))
        XCTAssertTrue(yaml.contains("author: \"Alice\""))
        XCTAssertTrue(yaml.contains("text: \"Review this\""))
    }

    func testCommentReplyCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        doc.comments.addComment(Comment(id: 1, author: "Alice", text: "Review", paragraphIndex: 0))
        _ = doc.comments.addReply(to: 1, author: "Bob", text: "Done")
        doc.appendParagraph(Paragraph(text: "Text"))
        collector.collectDocument(doc)

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("parentId: 1"))
    }

    func testCommentDoneStatus() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        doc.comments.addComment(Comment(id: 1, author: "Alice", text: "Check", paragraphIndex: 0))
        doc.comments.markAsDone(1)
        doc.appendParagraph(Paragraph(text: "Text"))
        collector.collectDocument(doc)

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("done: true"))
    }

    // MARK: - Numbering Definitions

    func testNumberingDefinitionCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        _ = doc.numbering.createBulletList()
        doc.appendParagraph(Paragraph(text: "Item"))
        collector.collectDocument(doc)

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("numbering:"))
        XCTAssertTrue(yaml.contains("abstractNumId: 0"))
        XCTAssertTrue(yaml.contains("numFmt: bullet"))
    }

    func testNumberedListDefinitionCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        _ = doc.numbering.createNumberedList()
        doc.appendParagraph(Paragraph(text: "Item"))
        collector.collectDocument(doc)

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("numFmt: decimal"))
        XCTAssertTrue(yaml.contains("numFmt: lowerLetter"))
    }

    // MARK: - Document Properties Enhancement

    func testKeywordsCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        doc.properties.keywords = "swift, docx, converter"
        doc.appendParagraph(Paragraph(text: "Text"))
        collector.collectDocument(doc)

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("keywords: \"swift, docx, converter\""))
    }

    // MARK: - Paragraph Advanced Properties

    func testKeepNextCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = ParagraphProperties()
        props.keepNext = true
        doc.appendParagraph(Paragraph(text: "Keep with next", properties: props))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("keepNext: true"))
    }

    func testKeepLinesCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = ParagraphProperties()
        props.keepLines = true
        doc.appendParagraph(Paragraph(text: "Keep lines", properties: props))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("keepLines: true"))
    }

    func testPageBreakBeforeCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = ParagraphProperties()
        props.pageBreakBefore = true
        doc.appendParagraph(Paragraph(text: "New page", properties: props))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("pageBreakBefore: true"))
    }

    func testParagraphBorderCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = ParagraphProperties()
        props.border = ParagraphBorder.all(ParagraphBorderStyle(type: .single, color: "FF0000", size: 8))
        doc.appendParagraph(Paragraph(text: "Bordered", properties: props))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("border:"))
        XCTAssertTrue(yaml.contains("type: single"))
        XCTAssertTrue(yaml.contains("color: \"FF0000\""))
    }

    func testParagraphShadingCollection() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = ParagraphProperties()
        props.shading = ParagraphShading(fill: "FFFF00")
        doc.appendParagraph(Paragraph(text: "Shaded", properties: props))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("shading:"))
        XCTAssertTrue(yaml.contains("fill: \"FFFF00\""))
    }

    // MARK: - lineRule (PsychQuant/macdoc#220 item 1)

    func testSpacingLineRuleIsWrittenToYAML() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = ParagraphProperties()
        props.spacing = Spacing(before: 240, after: 120, line: 360, lineRule: .exact)
        doc.appendParagraph(Paragraph(text: "Exact line spacing", properties: props))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("spacing:"))
        XCTAssertTrue(yaml.contains("lineRule: exact"), "lineRule must appear inside the spacing map; got:\n\(yaml)")
    }

    func testSpacingWithoutLineRuleOmitsTheField() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = ParagraphProperties()
        props.spacing = Spacing(before: 240) // no lineRule set
        doc.appendParagraph(Paragraph(text: "No line rule", properties: props))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertFalse(yaml.contains("lineRule"), "lineRule must not appear when the original spacing had none; got:\n\(yaml)")
    }

    func testAllThreeLineRuleValuesRoundTripToYAML() throws {
        for (rule, expected) in [(LineRule.auto, "auto"), (.exact, "exact"), (.atLeast, "atLeast")] {
            var collector = MetadataCollector()
            var doc = WordDocument()
            var props = ParagraphProperties()
            props.spacing = Spacing(line: 240, lineRule: rule)
            doc.appendParagraph(Paragraph(text: "Line rule \(expected)", properties: props))
            collector.collectDocument(doc)
            for (index, child) in doc.body.children.enumerated() {
                collector.collectElement(child, index: index)
            }
            let yaml = try makeYAML(from: collector)
            XCTAssertTrue(yaml.contains("lineRule: \(expected)"), "Expected lineRule: \(expected) in:\n\(yaml)")
        }
    }

    // MARK: - textFingerprint (PsychQuant/macdoc#220 item 5)

    func testParagraphWithLayerCPropertyGetsATextFingerprint() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = ParagraphProperties()
        props.alignment = .center
        doc.appendParagraph(Paragraph(text: "Centered paragraph text", properties: props))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        XCTAssertTrue(yaml.contains("textFingerprint:"), "Every recorded paragraph entry must carry a textFingerprint; got:\n\(yaml)")

        let expected = ParagraphFingerprint.loose("Centered paragraph text")
        XCTAssertTrue(yaml.contains("textFingerprint: \"\(expected)\""), "Fingerprint must match ParagraphFingerprint.loose over the paragraph's run text; got:\n\(yaml)")
    }

    func testDifferentParagraphTextProducesDifferentFingerprintInYAML() throws {
        func fingerprintYAML(for text: String) throws -> String {
            var collector = MetadataCollector()
            var doc = WordDocument()
            var props = ParagraphProperties()
            props.alignment = .center
            doc.appendParagraph(Paragraph(text: text, properties: props))
            collector.collectDocument(doc)
            for (index, child) in doc.body.children.enumerated() {
                collector.collectElement(child, index: index)
            }
            return try makeYAML(from: collector)
        }

        let yamlA = try fingerprintYAML(for: "First version of the text")
        let yamlB = try fingerprintYAML(for: "A completely different sentence")
        XCTAssertNotEqual(yamlA, yamlB)
    }

    func testParagraphAlsoGetsAnExactTextFingerprint() throws {
        var collector = MetadataCollector()

        var doc = WordDocument()
        var props = ParagraphProperties()
        props.alignment = .center
        doc.appendParagraph(Paragraph(text: "Centered paragraph text", properties: props))
        collector.collectDocument(doc)

        for (index, child) in doc.body.children.enumerated() {
            collector.collectElement(child, index: index)
        }

        let yaml = try makeYAML(from: collector)
        let expected = ParagraphFingerprint.exact("Centered paragraph text")
        XCTAssertTrue(yaml.contains("exactTextFingerprint: \"\(expected)\""), "got:\n\(yaml)")
    }
}
