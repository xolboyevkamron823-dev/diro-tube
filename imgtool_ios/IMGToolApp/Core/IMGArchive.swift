import Foundation
import Combine

public enum IMGError: LocalizedError {
    case invalidHeader
    case fileNotFound
    case readFailed
    case writeFailed
    case invalidEntry
    case securityScopedAccessDenied
    
    public var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "Fayl formati noto'g'ri. Faqat GTA IMG VER2 (San Andreas / Vice City) arxivlari qo'llab-quvvatlanadi."
        case .fileNotFound:
            return "Arxiv fayli topilmadi."
        case .readFailed:
            return "Faylni o'qishda xatolik yuz berdi."
        case .writeFailed:
            return "Faylga yozishda xatolik yuz berdi."
        case .invalidEntry:
            return "Tanlangan element arxivda topilmadi."
        case .securityScopedAccessDenied:
            return "iOS tizimi faylga kirish ruxsatini bermadi."
        }
    }
}

public class IMGArchive: ObservableObject {
    @Published public var entries: [IMGEntry] = []
    @Published public var archiveURL: URL?
    @Published public var archiveName: String = ""
    @Published public var archiveSizeFormatted: String = ""
    @Published public var isLoaded: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private var isSecurityScoped: Bool = false
    private let sectorSize: UInt64 = 2048
    
    public init() {}
    
    deinit {
        closeArchive()
    }
    
    public func closeArchive() {
        if isSecurityScoped, let url = archiveURL {
            url.stopAccessingSecurityScopedResource()
            isSecurityScoped = false
        }
        entries = []
        archiveURL = nil
        archiveName = ""
        archiveSizeFormatted = ""
        isLoaded = false
        isLoading = false
    }
    
    // MARK: - Open / Load Archive
    public func load(from url: URL) {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var didStartAccess = false
            if url.startAccessingSecurityScopedResource() {
                didStartAccess = true
            }
            
            do {
                guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
                    throw IMGError.readFailed
                }
                defer { try? fileHandle.close() }
                
                // Read 8-byte header: 4 bytes Magic ("VER2"), 4 bytes Count
                let headerData = fileHandle.readData(ofLength: 8)
                guard headerData.count == 8 else {
                    throw IMGError.invalidHeader
                }
                
                let magic = String(data: headerData[0..<4], encoding: .ascii) ?? ""
                guard magic == "VER2" else {
                    throw IMGError.invalidHeader
                }
                
                let count = headerData[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }
                
                // Read entire directory table: count * 32 bytes in a single fast I/O call
                let dirTableSize = Int(count) * 32
                let dirData = fileHandle.readData(ofLength: dirTableSize)
                guard dirData.count == dirTableSize else {
                    throw IMGError.readFailed
                }
                
                var parsedEntries: [IMGEntry] = []
                parsedEntries.reserveCapacity(Int(count))
                
                dirData.withUnsafeBytes { rawBuffer in
                    for i in 0..<Int(count) {
                        let offsetInDir = i * 32
                        let offset = rawBuffer.load(fromByteOffset: offsetInDir, as: UInt32.self)
                        let streamSize = rawBuffer.load(fromByteOffset: offsetInDir + 4, as: UInt16.self)
                        let size = rawBuffer.load(fromByteOffset: offsetInDir + 6, as: UInt16.self)
                        
                        let nameBytes = rawBuffer.baseAddress!.advanced(by: offsetInDir + 8)
                        let nameData = Data(bytes: nameBytes, count: 24)
                        let nameString = (String(data: nameData, encoding: .ascii) ?? "unnamed")
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                        
                        let entry = IMGEntry(
                            index: i,
                            name: nameString,
                            offset: offset,
                            streamingSize: streamSize,
                            size: size
                        )
                        parsedEntries.append(entry)
                    }
                }
                
                // Calculate file size
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = (attributes?[.size] as? Int64) ?? 0
                let sizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                
                DispatchQueue.main.async {
                    self.archiveURL = url
                    self.archiveName = url.lastPathComponent
                    self.archiveSizeFormatted = sizeStr
                    self.entries = parsedEntries
                    self.isSecurityScoped = didStartAccess
                    self.isLoaded = true
                    self.isLoading = false
                }
            } catch {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Extract Entry Data
    public func extractData(for entry: IMGEntry) throws -> Data {
        guard let url = archiveURL else { throw IMGError.fileNotFound }
        
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        let byteOffset = UInt64(entry.offset) * sectorSize
        try fileHandle.seek(toOffset: byteOffset)
        
        let readLength = entry.sectors * 2048
        let sectorData = fileHandle.readData(ofLength: readLength)
        
        // If it's a RenderWare file (DFF or TXD), inspect chunk header to return exact byte count
        if sectorData.count >= 12, entry.isDFF || entry.isTXD {
            let rwChunk = sectorData[0..<4].withUnsafeBytes { $0.load(as: UInt32.self) }
            let rwSize = sectorData[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }
            
            // 0x10 = Clump (DFF), 0x16 = TexDictionary (TXD)
            if (rwChunk == 0x10 || rwChunk == 0x16) && (12 + Int(rwSize) <= sectorData.count) {
                return sectorData.subdata(in: 0..<(12 + Int(rwSize)))
            }
        }
        
        return sectorData
    }
    
    // MARK: - Extract to File (for Share Sheet / Files app)
    public func extractToFile(entry: IMGEntry) throws -> URL {
        let data = try extractData(for: entry)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("IMGTool_Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        
        let destURL = tempDir.appendingPathComponent(entry.name)
        try data.write(to: destURL, options: .atomic)
        return destURL
    }
    
    // MARK: - 1-Click Replace (Fast In-Place or Instant Append)
    public func replace(entry: IMGEntry, withSourceURL sourceURL: URL) throws {
        guard let url = archiveURL else { throw IMGError.fileNotFound }
        
        var didStartSecurity = false
        if sourceURL.startAccessingSecurityScopedResource() {
            didStartSecurity = true
        }
        defer {
            if didStartSecurity {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let newData = try Data(contentsOf: sourceURL)
        guard newData.count > 0 else { throw IMGError.readFailed }
        
        let requiredSectors = UInt16((newData.count + 2047) / 2048)
        let paddedLength = Int(requiredSectors) * 2048
        var paddedData = newData
        if paddedData.count < paddedLength {
            paddedData.append(contentsOf: [UInt8](repeating: 0, count: paddedLength - paddedData.count))
        }
        
        let fileHandle = try FileHandle(forUpdating: url)
        defer {
            try? fileHandle.synchronize()
            try? fileHandle.close()
        }
        
        var updatedEntry = entry
        
        if requiredSectors <= entry.sectors {
            // ⚡ FAST IN-PLACE WRITE (0.01 sec)
            let byteOffset = UInt64(entry.offset) * sectorSize
            try fileHandle.seek(toOffset: byteOffset)
            try fileHandle.write(contentsOf: paddedData)
            
            // Update sector count in directory entry (streamingSize at offset +4)
            let dirEntryOffset = 8 + UInt64(entry.index * 32) + 4
            try fileHandle.seek(toOffset: dirEntryOffset)
            var littleEndianSectors = requiredSectors.littleEndian
            try fileHandle.write(contentsOf: Data(bytes: &littleEndianSectors, count: 2))
            
            updatedEntry.streamingSize = requiredSectors
        } else {
            // ⚡ FAST APPEND (0.02 sec)
            let endOffset = try fileHandle.seekToEnd()
            // Sector-align end offset
            let alignedEndOffset = (endOffset + (sectorSize - 1)) / sectorSize * sectorSize
            if alignedEndOffset > endOffset {
                let padBytes = Int(alignedEndOffset - endOffset)
                try fileHandle.write(contentsOf: Data(repeating: 0, count: padBytes))
            }
            
            let newSectorOffset = UInt32(alignedEndOffset / sectorSize)
            try fileHandle.write(contentsOf: paddedData)
            
            // Update directory entry: offset (4 bytes) + streamingSize (2 bytes)
            let dirEntryOffset = 8 + UInt64(entry.index * 32)
            try fileHandle.seek(toOffset: dirEntryOffset)
            
            var newOffsetLE = newSectorOffset.littleEndian
            var newSectorsLE = requiredSectors.littleEndian
            try fileHandle.write(contentsOf: Data(bytes: &newOffsetLE, count: 4))
            try fileHandle.write(contentsOf: Data(bytes: &newSectorsLE, count: 2))
            
            updatedEntry.offset = newSectorOffset
            updatedEntry.streamingSize = requiredSectors
        }
        
        // Update in-memory entry
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                self.entries[idx] = updatedEntry
            }
        }
    }
    
    // MARK: - Add New File
    public func addFile(from sourceURL: URL) throws {
        guard let url = archiveURL else { throw IMGError.fileNotFound }
        
        var didStart = false
        if sourceURL.startAccessingSecurityScopedResource() {
            didStart = true
        }
        defer {
            if didStart { sourceURL.stopAccessingSecurityScopedResource() }
        }
        
        let fileData = try Data(contentsOf: sourceURL)
        let fileName = sourceURL.lastPathComponent.lowercased()
        
        // If file already exists, do a replace
        if let existing = entries.first(where: { $0.name.lowercased() == fileName }) {
            try replace(entry: existing, withSourceURL: sourceURL)
            return
        }
        
        let requiredSectors = UInt16((fileData.count + 2047) / 2048)
        let paddedLength = Int(requiredSectors) * 2048
        var paddedData = fileData
        if paddedData.count < paddedLength {
            paddedData.append(contentsOf: [UInt8](repeating: 0, count: paddedLength - paddedData.count))
        }
        
        let fileHandle = try FileHandle(forUpdating: url)
        defer {
            try? fileHandle.synchronize()
            try? fileHandle.close()
        }
        
        // Write padded data at end of file
        let endOffset = try fileHandle.seekToEnd()
        let alignedEndOffset = (endOffset + (sectorSize - 1)) / sectorSize * sectorSize
        if alignedEndOffset > endOffset {
            try fileHandle.write(contentsOf: Data(repeating: 0, count: Int(alignedEndOffset - endOffset)))
        }
        let newSectorOffset = UInt32(alignedEndOffset / sectorSize)
        try fileHandle.write(contentsOf: paddedData)
        
        // Read existing count
        try fileHandle.seek(toOffset: 4)
        let countData = fileHandle.readData(ofLength: 4)
        var count = countData.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // Create 32-byte directory entry
        var dirEntryData = Data(capacity: 32)
        var offLE = newSectorOffset.littleEndian
        var secLE = requiredSectors.littleEndian
        var zero16: UInt16 = 0
        dirEntryData.append(contentsOf: Data(bytes: &offLE, count: 4))
        dirEntryData.append(contentsOf: Data(bytes: &secLE, count: 2))
        dirEntryData.append(contentsOf: Data(bytes: &zero16, count: 2))
        
        var nameBytes = [UInt8](repeating: 0, count: 24)
        let nameASCII = Array(fileName.utf8.prefix(23))
        for (i, b) in nameASCII.enumerated() {
            nameBytes[i] = b
        }
        dirEntryData.append(contentsOf: nameBytes)
        
        // Write new directory entry at 8 + count * 32
        let newDirOffset = 8 + UInt64(count) * 32
        try fileHandle.seek(toOffset: newDirOffset)
        try fileHandle.write(contentsOf: dirEntryData)
        
        // Increment count in header
        count += 1
        var newCountLE = count.littleEndian
        try fileHandle.seek(toOffset: 4)
        try fileHandle.write(contentsOf: Data(bytes: &newCountLE, count: 4))
        
        let newEntry = IMGEntry(
            index: Int(count - 1),
            name: fileName,
            offset: newSectorOffset,
            streamingSize: requiredSectors,
            size: 0
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.entries.append(newEntry)
        }
    }
    
    // MARK: - Delete File
    public func delete(entry: IMGEntry) throws {
        guard let url = archiveURL else { throw IMGError.fileNotFound }
        
        let fileHandle = try FileHandle(forUpdating: url)
        defer {
            try? fileHandle.synchronize()
            try? fileHandle.close()
        }
        
        // Read header count
        try fileHandle.seek(toOffset: 4)
        let countData = fileHandle.readData(ofLength: 4)
        var count = countData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard count > 0 else { return }
        
        guard let removeIdx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updatedEntries = entries
        updatedEntries.remove(at: removeIdx)
        
        // Rewrite directory table
        var dirData = Data(capacity: updatedEntries.count * 32)
        for ent in updatedEntries {
            var offLE = ent.offset.littleEndian
            var secLE = ent.streamingSize.littleEndian
            var zero16: UInt16 = 0
            dirData.append(contentsOf: Data(bytes: &offLE, count: 4))
            dirData.append(contentsOf: Data(bytes: &secLE, count: 2))
            dirData.append(contentsOf: Data(bytes: &zero16, count: 2))
            
            var nameBytes = [UInt8](repeating: 0, count: 24)
            let nameASCII = Array(ent.name.utf8.prefix(23))
            for (i, b) in nameASCII.enumerated() {
                nameBytes[i] = b
            }
            dirData.append(contentsOf: nameBytes)
        }
        
        try fileHandle.seek(toOffset: 8)
        try fileHandle.write(contentsOf: dirData)
        
        // Update count
        count = UInt32(updatedEntries.count)
        var newCountLE = count.littleEndian
        try fileHandle.seek(toOffset: 4)
        try fileHandle.write(contentsOf: Data(bytes: &newCountLE, count: 4))
        
        // Re-index
        for i in 0..<updatedEntries.count {
            updatedEntries[i].index = i
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.entries = updatedEntries
        }
    }
    
    // MARK: - Rebuild Archive (Clean Defragmentation)
    public func rebuildArchive(progress: @escaping (Double) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let sourceURL = archiveURL else {
            completion(.failure(IMGError.fileNotFound))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let tempRebuiltURL = FileManager.default.temporaryDirectory.appendingPathComponent("rebuilt_\(UUID().uuidString).img")
            
            do {
                let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
                defer { try? sourceHandle.close() }
                
                FileManager.default.createFile(atPath: tempRebuiltURL.path, contents: nil, attributes: nil)
                let destHandle = try FileHandle(forWritingTo: tempRebuiltURL)
                defer { try? destHandle.close() }
                
                let activeEntries = self.entries
                let count = UInt32(activeEntries.count)
                
                // 1. Write Header: "VER2" + count
                var headerData = Data("VER2".utf8)
                var countLE = count.littleEndian
                headerData.append(contentsOf: Data(bytes: &countLE, count: 4))
                try destHandle.write(contentsOf: headerData)
                
                // 2. Calculate data start sector
                let dirBytes = 8 + UInt64(count) * 32
                let dataStartSector = (dirBytes + (self.sectorSize - 1)) / self.sectorSize
                
                // Write placeholder for directory table + padding
                let placeholderDir = Data(repeating: 0, count: Int(dataStartSector * self.sectorSize - 8))
                try destHandle.write(contentsOf: placeholderDir)
                
                var currentSector = UInt32(dataStartSector)
                var newEntries: [IMGEntry] = []
                newEntries.reserveCapacity(activeEntries.count)
                
                var newDirData = Data(capacity: activeEntries.count * 32)
                
                // 3. Stream each file's data
                for (i, entry) in activeEntries.enumerated() {
                    let oldByteOffset = UInt64(entry.offset) * self.sectorSize
                    try sourceHandle.seek(toOffset: oldByteOffset)
                    let entryData = sourceHandle.readData(ofLength: entry.sectors * 2048)
                    
                    try destHandle.seek(toOffset: UInt64(currentSector) * self.sectorSize)
                    try destHandle.write(contentsOf: entryData)
                    
                    var entryCopy = entry
                    entryCopy.offset = currentSector
                    entryCopy.index = i
                    newEntries.append(entryCopy)
                    
                    // Build 32-byte dir entry
                    var offLE = currentSector.littleEndian
                    var secLE = entry.streamingSize.littleEndian
                    var zero16: UInt16 = 0
                    newDirData.append(contentsOf: Data(bytes: &offLE, count: 4))
                    newDirData.append(contentsOf: Data(bytes: &secLE, count: 2))
                    newDirData.append(contentsOf: Data(bytes: &zero16, count: 2))
                    
                    var nameBytes = [UInt8](repeating: 0, count: 24)
                    let nameASCII = Array(entry.name.utf8.prefix(23))
                    for (k, b) in nameASCII.enumerated() {
                        nameBytes[k] = b
                    }
                    newDirData.append(contentsOf: nameBytes)
                    
                    currentSector += UInt32(entry.sectors)
                    
                    if i % 100 == 0 || i == activeEntries.count - 1 {
                        let pct = Double(i + 1) / Double(activeEntries.count)
                        DispatchQueue.main.async {
                            progress(pct)
                        }
                    }
                }
                
                // 4. Write completed directory table at offset 8
                try destHandle.seek(toOffset: 8)
                try destHandle.write(contentsOf: newDirData)
                try destHandle.synchronize()
                
                // 5. Replace original file atomically
                _ = try FileManager.default.replaceItemAt(sourceURL, withItemAt: tempRebuiltURL)
                
                DispatchQueue.main.async {
                    self.entries = newEntries
                    // Update size
                    let attr = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
                    let sz = (attr?[.size] as? Int64) ?? 0
                    self.archiveSizeFormatted = ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
                    completion(.success(()))
                }
            } catch {
                try? FileManager.default.removeItem(at: tempRebuiltURL)
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
