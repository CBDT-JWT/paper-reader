import Foundation

public struct Paper: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public let importedAt: Date
    public var page: Int
    public var folderID: UUID?
    public var readingPoint: PDFPoint?
    public var metadata: Bibliography?
    public var scale: Double
    public init(id: UUID = UUID(), title: String, importedAt: Date = .now, page: Int = 0, scale: Double = 0) {
        self.id = id; self.title = title; self.importedAt = importedAt; self.page = page; self.scale = scale
    }
}

public struct SourceReference: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let paperID: UUID
    public let page: Int // zero-based
    public let rect: PDFRect
    public let asset: String?
    public let text: String?
    public init(id: UUID = UUID(), paperID: UUID, page: Int, rect: PDFRect, asset: String? = nil, text: String? = nil) {
        self.id = id; self.paperID = paperID; self.page = page; self.rect = rect; self.asset = asset; self.text = text
    }
    public var link: String { "paperreader://source/\(id.uuidString)" }
}

public struct PDFRect: Codable, Sendable, Equatable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public init(_ rect: CGRect) { self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }
}

public struct NoteSnapshot: Sendable {
    public let markdown: String
    public let revision: String
}

public enum LibraryError: LocalizedError {
    case database(String), invalidPDF, missingPaper, externalChange, invalidPath, oversizedImage
    public var errorDescription: String? {
        switch self {
        case .database(let message): return L("数据库错误：\(message)")
        case .invalidPDF: return L("无法读取这个 PDF 文件。")
        case .missingPaper: return L("找不到论文文件。")
        case .externalChange: return L("笔记已被其他程序修改。你的编辑已保存在冲突副本中，请重新打开论文以读取外部版本。")
        case .invalidPath: return L("资源路径不在允许的目录内。")
        case .oversizedImage: return L("截图区域过大，请选择较小区域。")
        }
    }
}
