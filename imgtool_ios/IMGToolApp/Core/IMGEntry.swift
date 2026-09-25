import Foundation
import SwiftUI

public enum IMGEntryType: String, CaseIterable, Identifiable {
    case all = "Barchasi"
    case dff = "DFF Modellar"
    case txd = "TXD Tekstura"
    case col = "COL Kolliziya"
    case ifp = "IFP Animatsiya"
    case other = "Boshqalar"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .dff: return "car.fill"
        case .txd: return "photo.stack.fill"
        case .col: return "cube.transparent.fill"
        case .ifp: return "figure.walk"
        case .other: return "doc.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .all: return .blue
        case .dff: return .orange
        case .txd: return .cyan
        case .col: return .green
        case .ifp: return .purple
        case .other: return .gray
        }
    }
}

public struct IMGEntry: Identifiable, Hashable {
    public let id: UUID
    public var index: Int
    public var name: String
    public var offset: UInt32      // Sector index
    public var streamingSize: UInt16 // Sectors
    public var size: UInt16          // Sectors (usually 0 in SA, or used in other formats)
    
    public init(id: UUID = UUID(), index: Int, name: String, offset: UInt32, streamingSize: UInt16, size: UInt16) {
        self.id = id
        self.index = index
        self.name = name
        self.offset = offset
        self.streamingSize = streamingSize
        self.size = size
    }
    
    public var sectors: Int {
        if streamingSize > 0 {
            return Int(streamingSize)
        } else if size > 0 {
            return Int(size)
        }
        return 1
    }
    
    public var byteSize: Int {
        return sectors * 2048
    }
    
    public var formattedSize: String {
        let bytes = Double(byteSize)
        if bytes >= 1024 * 1024 {
            return String(format: "%.2f MB", bytes / (1024.0 * 1024.0))
        } else {
            return String(format: "%.1f KB", bytes / 1024.0)
        }
    }
    
    public var fileExtension: String {
        let parts = name.split(separator: ".")
        if parts.count > 1 {
            return String(parts.last!).lowercased()
        }
        return ""
    }
    
    public var entryType: IMGEntryType {
        switch fileExtension {
        case "dff": return .dff
        case "txd": return .txd
        case "col": return .col
        case "ifp": return .ifp
        default: return .other
        }
    }
    
    public var isDFF: Bool {
        return fileExtension == "dff"
    }
    
    public var isTXD: Bool {
        return fileExtension == "txd"
    }
}
