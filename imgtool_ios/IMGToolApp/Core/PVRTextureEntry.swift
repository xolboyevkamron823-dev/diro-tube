import Foundation
import UIKit

public enum PVRFormat: String, CaseIterable, Identifiable {
    case pvrtc2bpp = "2BPP"
    case pvrtc4bpp = "4BPP"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .pvrtc2bpp: return "PVRTC 2BPP (Tezkor va Standart)"
        case .pvrtc4bpp: return "PVRTC 4BPP (Yuqori Sifat)"
        }
    }
}

public class PVRTextureEntry: Identifiable, ObservableObject {
    public let id = UUID()
    public let index: Int
    
    @Published public var name: String
    @Published public var width: Int
    @Published public var height: Int
    @Published public var format: PVRFormat
    @Published public var isModified: Bool = false
    @Published public var isNew: Bool = false
    
    public var offset: UInt32
    public var size: UInt32
    public var val0: UInt32
    public var rawTxtLine: String
    
    // In-memory modified chunk (16-byte header + PVRTC payload)
    public var modifiedChunk: Data? = nil
    
    // Cached decoded thumbnail/image for smooth scrolling
    public var cachedPreview: UIImage? = nil
    
    public init(index: Int, name: String, width: Int, height: Int, format: PVRFormat, offset: UInt32, size: UInt32, val0: UInt32, rawTxtLine: String = "") {
        self.index = index
        self.name = name
        self.width = width
        self.height = height
        self.format = format
        self.offset = offset
        self.size = size
        self.val0 = val0
        self.rawTxtLine = rawTxtLine
    }
    
    public var sizeString: String {
        let kb = Double(size) / 1024.0
        if kb >= 1024.0 {
            return String(format: "%.2f MB", kb / 1024.0)
        }
        return String(format: "%.1f KB", kb)
    }
    
    public var dimensionsString: String {
        return "\(width) × \(height) px"
    }
}
