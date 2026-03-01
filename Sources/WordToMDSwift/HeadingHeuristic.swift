import OOXMLSwift

/// 統計推斷 heading level（Practical Mode）
///
/// 演算法：
/// 1. 掃描全文段落的 font size（跳過已有 heading style 的）
/// 2. 出現最多的 font size = body text
/// 3. 比 body 大且 bold + 短段落 → heading 候選
/// 4. 候選按大小排序 → H1, H2, H3...
struct HeadingHeuristic {
    private var sizeToLevel: [Int: Int] = [:]  // fontSize (half-points) → heading level

    /// 分析文件中的段落，建立 fontSize → heading level 對照表
    mutating func analyze(children: [BodyChild], styles: [Style]) {
        // 收集 font size 分佈
        var sizeCounts: [Int: Int] = [:]  // fontSize → 段落數
        var headingSizes: Set<Int> = []   // 候選 heading 的 size

        for child in children {
            guard case .paragraph(let para) = child else { continue }
            // 跳過已有 heading style 的段落
            if let style = para.properties.style,
               isHeadingStyle(style, styles: styles) { continue }

            guard let fontSize = effectiveFontSize(para) else { continue }
            sizeCounts[fontSize, default: 0] += 1
        }

        guard !sizeCounts.isEmpty else { return }

        // body size = 出現最多的
        let bodySize = sizeCounts.max(by: { $0.value < $1.value })!.key

        // 比 body 大的 → 候選（還要檢查 bold + 段落短）
        for child in children {
            guard case .paragraph(let para) = child else { continue }
            if let style = para.properties.style,
               isHeadingStyle(style, styles: styles) { continue }

            guard let fontSize = effectiveFontSize(para),
                  fontSize > bodySize else { continue }

            let isBold = para.runs.allSatisfy {
                $0.properties.bold || $0.text.trimmingCharacters(in: .whitespaces).isEmpty
            }
            let isShort = para.getText().count < 200

            if isBold && isShort {
                headingSizes.insert(fontSize)
            }
        }

        // 按大小排序 → 對應 H1~H6
        let sorted = headingSizes.sorted(by: >)
        for (index, size) in sorted.prefix(6).enumerated() {
            sizeToLevel[size] = index + 1
        }
    }

    /// 推斷段落的 heading level
    /// - Returns: 1~6（H1~H6），或 nil 表示不是 heading
    func inferLevel(for paragraph: Paragraph) -> Int? {
        guard let fontSize = effectiveFontSize(paragraph) else { return nil }
        guard let level = sizeToLevel[fontSize] else { return nil }

        // 額外驗證：bold + 段落短
        let isBold = paragraph.runs.allSatisfy {
            $0.properties.bold || $0.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let isShort = paragraph.getText().count < 200
        guard isBold && isShort else { return nil }

        return level
    }

    // MARK: - Private

    /// 取得段落的有效 font size
    private func effectiveFontSize(_ paragraph: Paragraph) -> Int? {
        let sizes = paragraph.runs.compactMap { $0.properties.fontSize }
        guard !sizes.isEmpty else { return nil }
        // 如果所有 run 同 size，用該值；否則用最大值
        return sizes.max()
    }

    /// 檢查 style 是否為 heading（與 WordConverter.detectHeadingLevel 相同的模式）
    private func isHeadingStyle(_ styleName: String, styles: [Style]) -> Bool {
        let lower = styleName.lowercased()
        let patterns = ["heading", "標題", "title", "subtitle"]
        return patterns.contains(where: { lower.contains($0) })
    }
}
