import Foundation
import OOXMLSwift

/// 圖片提取器（Tier 2+）
///
/// 負責將 WordDocument 中的 ImageReference（含 binary data）寫入 figures 目錄。
/// 回傳相對路徑供 Markdown 引用：`![alt](figures/image1.png)`
struct FigureExtractor {
    let directory: URL
    private var extractedIds: Set<String> = []

    init(directory: URL) {
        self.directory = directory
    }

    /// 建立 figures 目錄（如果不存在）
    func createDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    /// 提取圖片到 figures 目錄
    /// - Returns: 相對路徑（如 `figures/image1.png`）
    mutating func extract(_ imageRef: ImageReference) throws -> String {
        // 避免重複提取
        guard !extractedIds.contains(imageRef.id) else {
            return relativePath(for: imageRef.fileName)
        }

        let fileURL = directory.appendingPathComponent(imageRef.fileName)
        try imageRef.data.write(to: fileURL)
        extractedIds.insert(imageRef.id)

        return relativePath(for: imageRef.fileName)
    }

    private func relativePath(for fileName: String) -> String {
        "figures/\(fileName)"
    }
}
