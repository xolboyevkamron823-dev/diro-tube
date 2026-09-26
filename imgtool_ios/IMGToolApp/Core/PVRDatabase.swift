import Foundation
import UIKit
import Combine

public enum PVRError: LocalizedError {
    case fileNotFound
    case readFailed
    case writeFailed
    case invalidTOC
    case tocMissing
    case invalidHeader
    case compressionFailed
    case decompressionFailed
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "PVR fayli topilmadi."
        case .readFailed:
            return "PVR faylini o'qishda xatolik yuz berdi."
        case .writeFailed:
            return "PVR bazasini saqlashda xatolik yuz berdi."
        case .invalidTOC:
            return "TOC indeks fayli formati noto'g'ri yoki fayl buzilgan."
        case .tocMissing:
            return "TOC indeks fayli tanlanmadi! gta3.pvr.dat bilan birga gta3.pvr.toc faylini ham tanlang."
        case .invalidHeader:
            return "War Drum PVR sarlavhasi noto'g'ri."
        case .compressionFailed:
            return "Rasmni PVRTC formatiga siqish amalga oshmadi."
        case .decompressionFailed:
            return "PVRTC teksturasini ochib bo'lmadi."
        }
    }
}

public class PVRDatabase: ObservableObject {
    @Published public var entries: [PVRTextureEntry] = []
    @Published public var datURL: URL? = nil
    @Published public var tocURL: URL? = nil
    @Published public var txtURL: URL? = nil
    @Published public var szURL: URL? = nil
    
    @Published public var databaseName: String = ""
    @Published public var isLoaded: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var loadingProgress: Double = 0.0
    @Published public var loadingStatus: String = ""
    @Published public var errorMessage: String? = nil
    
    @Published public var txtHeaderLine: String = "cat=0 name=Default onfoot=5 slow=5 fast=5 defaultformat=2 defaultstream=0"
    
    private var accessedURLs: [URL] = []
    
    public init() {}
    
    deinit {
        closeDatabase()
    }
    
    public var hasUnsavedChanges: Bool {
        entries.contains { $0.isModified || $0.isNew }
    }
    
    public var modifiedCount: Int {
        entries.filter { $0.isModified || $0.isNew }.count
    }
    
    private func startAccess(_ url: URL?) {
        guard let u = url else { return }
        if u.startAccessingSecurityScopedResource() {
            if !accessedURLs.contains(u) {
                accessedURLs.append(u)
            }
        }
    }
    
    public func closeDatabase() {
        for u in accessedURLs {
            u.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
        
        entries = []
        datURL = nil
        tocURL = nil
        txtURL = nil
        szURL = nil
        databaseName = ""
        isLoaded = false
        isLoading = false
        errorMessage = nil
    }
    
    // MARK: - Auto Companion Search
    public static func findCompanions(for datURL: URL) -> (toc: URL?, txt: URL?, sz: URL?) {
        let folder = datURL.deletingLastPathComponent()
        let filename = datURL.lastPathComponent
        let baseName = filename
            .replacingOccurrences(of: ".pvr.dat", with: "")
            .replacingOccurrences(of: ".dat", with: "")
        
        let fileManager = FileManager.default
        
        // 1. TOC search
        let tocCandidates = [
            folder.appendingPathComponent("\(baseName).pvr.toc"),
            folder.appendingPathComponent("\(baseName).toc"),
            folder.appendingPathComponent("gta3.pvr.toc")
        ]
        let tocURL = tocCandidates.first { fileManager.fileExists(atPath: $0.path) }
        
        // 2. TXT search
        let txtCandidates = [
            folder.appendingPathComponent("\(baseName).txt"),
            folder.appendingPathComponent("\(baseName).pvr.txt"),
            folder.appendingPathComponent("gta3.txt")
        ]
        let txtURL = txtCandidates.first { fileManager.fileExists(atPath: $0.path) }
        
        // 3. SZ search
        let szCandidates = [
            folder.appendingPathComponent("\(baseName).pvr.sz"),
            folder.appendingPathComponent("\(baseName).sz"),
            folder.appendingPathComponent("gta3.pvr.sz")
        ]
        let szURL = szCandidates.first { fileManager.fileExists(atPath: $0.path) }
        
        return (tocURL, txtURL, szURL)
    }
    
    // MARK: - Load From URLs (Single or Multiple)
    public func loadFromURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        if urls.count == 1 && urls[0].hasDirectoryPath {
            loadFromFolder(folderURL: urls[0])
            return
        }
        
        var foundDat: URL? = nil
        var foundToc: URL? = nil
        var foundTxt: URL? = nil
        var foundSz: URL? = nil
        
        for u in urls {
            let name = u.lastPathComponent.lowercased()
            if name.hasSuffix(".pvr.dat") || (name.hasSuffix(".dat") && !name.contains(".tmb")) {
                foundDat = u
            } else if name.hasSuffix(".pvr.toc") || name.hasSuffix(".toc") {
                foundToc = u
            } else if name.hasSuffix(".txt") {
                foundTxt = u
            } else if name.hasSuffix(".pvr.sz") || name.hasSuffix(".sz") {
                foundSz = u
            }
        }
        
        if let d = foundDat {
            loadDatabase(fromDatURL: d, tocURL: foundToc, txtURL: foundTxt, szURL: foundSz)
        } else if let t = foundToc {
            let comp = Self.findCompanions(for: t)
            if let d = comp.toc { // check if dat exists
                loadDatabase(fromDatURL: d, tocURL: t, txtURL: foundTxt, szURL: foundSz)
            } else {
                self.errorMessage = "PVR.DAT fayli tanlanmadi! Iltimos, gta3.pvr.dat faylini ham tanlang."
            }
        } else {
            self.errorMessage = "Tanlangan fayllar orasida .pvr.dat yoki .pvr.toc fayllari topilmadi."
        }
    }
    
    // MARK: - Load From Folder
    public func loadFromFolder(folderURL: URL) {
        isLoading = true
        loadingProgress = 0.1
        loadingStatus = "Papka tahlil qilinmoqda..."
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var didAccessFolder = false
            if folderURL.startAccessingSecurityScopedResource() {
                didAccessFolder = true
                self.accessedURLs.append(folderURL)
            }
            
            let fileManager = FileManager.default
            var targetDat: URL? = nil
            var targetToc: URL? = nil
            var targetTxt: URL? = nil
            var targetSz: URL? = nil
            
            let searchDirs = [
                folderURL,
                folderURL.appendingPathComponent("texdb/gta3"),
                folderURL.appendingPathComponent("gta3"),
                folderURL.appendingPathComponent("texdb")
            ]
            
            for dir in searchDirs {
                if let items = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                    for item in items {
                        let name = item.lastPathComponent.lowercased()
                        if name.hasSuffix(".pvr.dat") || (name.hasSuffix(".dat") && !name.contains(".tmb")) {
                            if targetDat == nil || name.contains("gta3") { targetDat = item }
                        } else if name.hasSuffix(".pvr.toc") || name.hasSuffix(".toc") {
                            if targetToc == nil || name.contains("gta3") { targetToc = item }
                        } else if name.hasSuffix(".txt") {
                            if targetTxt == nil || name.contains("gta3") { targetTxt = item }
                        } else if name.hasSuffix(".pvr.sz") || name.hasSuffix(".sz") {
                            if targetSz == nil || name.contains("gta3") { targetSz = item }
                        }
                    }
                }
                if targetDat != nil && targetToc != nil { break }
            }
            
            if let d = targetDat, let t = targetToc {
                self.loadDatabase(fromDatURL: d, tocURL: t, txtURL: targetTxt, szURL: targetSz)
            } else {
                if didAccessFolder { folderURL.stopAccessingSecurityScopedResource() }
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Tanlangan papkada gta3.pvr.dat yoki gta3.pvr.toc fayli topilmadi."
                }
            }
        }
    }
    
    // MARK: - Load Database
    public func loadDatabase(fromDatURL datURL: URL, tocURL: URL? = nil, txtURL: URL? = nil, szURL: URL? = nil) {
        isLoading = true
        loadingProgress = 0.1
        loadingStatus = "Tekstura fayllari ochilmoqda..."
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.startAccess(datURL)
            self.startAccess(tocURL)
            self.startAccess(txtURL)
            self.startAccess(szURL)
            
            do {
                let companions = Self.findCompanions(for: datURL)
                let resolvedTOC = tocURL ?? companions.toc
                let resolvedTXT = txtURL ?? companions.txt
                let resolvedSZ = szURL ?? companions.sz
                
                self.startAccess(resolvedTOC)
                self.startAccess(resolvedTXT)
                self.startAccess(resolvedSZ)
                
                guard let finalTOC = resolvedTOC else {
                    throw PVRError.tocMissing
                }
                
                guard FileManager.default.fileExists(atPath: finalTOC.path) else {
                    throw PVRError.invalidTOC
                }
                
                DispatchQueue.main.async {
                    self.loadingStatus = "Indekslar o'qilmoqda (TOC)..."
                    self.loadingProgress = 0.25
                }
                
                let tocData = try Data(contentsOf: finalTOC)
                let totalEntries = tocData.count / 4
                guard totalEntries > 1 else {
                    throw PVRError.invalidTOC
                }
                
                var szData = Data()
                if let sURL = resolvedSZ, FileManager.default.fileExists(atPath: sURL.path) {
                    szData = (try? Data(contentsOf: sURL)) ?? Data()
                }
                
                var txtLines: [String] = []
                var localHeader = "cat=0 name=Default onfoot=5 slow=5 fast=5 defaultformat=2 defaultstream=0"
                if let tURL = resolvedTXT, FileManager.default.fileExists(atPath: tURL.path) {
                    if let content = try? String(contentsOf: tURL, encoding: .isoLatin1) {
                        txtLines = content.components(separatedBy: .newlines)
                        if let first = txtLines.first, !first.isEmpty {
                            localHeader = first
                        }
                    }
                }
                
                let fileHandle = try FileHandle(forReadingFrom: datURL)
                defer { try? fileHandle.close() }
                
                var parsedEntries: [PVRTextureEntry] = []
                parsedEntries.reserveCapacity(totalEntries - 1)
                
                let nameRegex = try? NSRegularExpression(pattern: "\"([^\"]+)\"")
                let wRegex = try? NSRegularExpression(pattern: "width=(\\d+)")
                let hRegex = try? NSRegularExpression(pattern: "height=(\\d+)")
                let fmtRegex = try? NSRegularExpression(pattern: "format=(\\d+)")
                
                DispatchQueue.main.async {
                    self.loadingStatus = "Tekstura yozuvlari tahlil qilinmoqda..."
                    self.loadingProgress = 0.4
                }
                
                tocData.withUnsafeBytes { (rawToc: UnsafeRawBufferPointer) in
                    let tocPtr = rawToc.bindMemory(to: UInt32.self)
                    
                    szData.withUnsafeBytes { (rawSz: UnsafeRawBufferPointer) in
                        let szPtr = rawSz.bindMemory(to: UInt32.self)
                        let hasSz = rawSz.count >= totalEntries * 4
                        
                        for i in 1..<totalEntries {
                            let off = tocPtr[i]
                            var sz: UInt32 = hasSz ? szPtr[i] : 0
                            
                            var texName = String(format: "texture_%04d", i)
                            var w = 128
                            var h = 128
                            var format: PVRFormat = .pvrtc2bpp
                            var lineStr = ""
                            var val0: UInt32 = 0
                            
                            if i < txtLines.count {
                                let line = txtLines[i]
                                lineStr = line
                                let nsLine = line as NSString
                                
                                if let mName = nameRegex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                                   mName.numberOfRanges > 1 {
                                    texName = nsLine.substring(with: mName.range(at: 1))
                                }
                                
                                if let mW = wRegex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                                   mW.numberOfRanges > 1 {
                                    w = Int(nsLine.substring(with: mW.range(at: 1))) ?? 128
                                }
                                
                                if let mH = hRegex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                                   mH.numberOfRanges > 1 {
                                    h = Int(nsLine.substring(with: mH.range(at: 1))) ?? 128
                                }
                                
                                if let mFmt = fmtRegex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                                   mFmt.numberOfRanges > 1 {
                                    let fmtVal = nsLine.substring(with: mFmt.range(at: 1))
                                    format = (fmtVal == "3" || fmtVal == "6") ? .pvrtc4bpp : .pvrtc2bpp
                                } else if hasSz && sz >= 16 {
                                    let payloadBytes = Int(sz - 16)
                                    if payloadBytes >= (w * h) / 2 {
                                        format = .pvrtc4bpp
                                    } else {
                                        format = .pvrtc2bpp
                                    }
                                }
                            } else {
                                lineStr = "\"\(texName)\""
                                try? fileHandle.seek(toOffset: UInt64(off))
                                let hdr = fileHandle.readData(ofLength: 16)
                                if hdr.count >= 16 {
                                    hdr.withUnsafeBytes { (hdrBuf: UnsafeRawBufferPointer) in
                                        val0 = hdrBuf.load(fromByteOffset: 0, as: UInt32.self)
                                        let w16 = hdrBuf.load(fromByteOffset: 4, as: UInt16.self)
                                        let h16 = hdrBuf.load(fromByteOffset: 6, as: UInt16.self)
                                        let cSz = hdrBuf.load(fromByteOffset: 8, as: UInt32.self)
                                        
                                        w = Int(w16)
                                        h = Int(h16 & 0x7FFF)
                                        if sz == 0 { sz = cSz }
                                        let payloadBytes = (sz >= 16) ? (sz - 16) : 0
                                        if (val0 >> 16) == 0x8C02 {
                                            format = .pvrtc4bpp
                                        } else if (val0 >> 16) == 0x8C01 {
                                            format = .pvrtc2bpp
                                        } else {
                                            format = (Int(payloadBytes) >= (w * h) / 2) ? .pvrtc4bpp : .pvrtc2bpp
                                        }
                                    }
                                }
                            }
                            
                            let entry = PVRTextureEntry(
                                index: i,
                                name: texName,
                                width: w,
                                height: h,
                                format: format,
                                offset: off,
                                size: sz,
                                val0: val0,
                                rawTxtLine: lineStr
                            )
                            parsedEntries.append(entry)
                        }
                    }
                }
                
                let dbBase = datURL.lastPathComponent
                    .replacingOccurrences(of: ".pvr.dat", with: "")
                    .replacingOccurrences(of: ".dat", with: "")
                
                DispatchQueue.main.async {
                    self.datURL = datURL
                    self.tocURL = finalTOC
                    self.txtURL = resolvedTXT
                    self.szURL = resolvedSZ
                    self.databaseName = dbBase.isEmpty ? "gta3" : dbBase
                    self.txtHeaderLine = localHeader
                    self.entries = parsedEntries
                    self.isLoaded = true
                    self.isLoading = false
                    self.loadingProgress = 1.0
                    self.loadingStatus = "Tayyor: \(parsedEntries.count) ta tekstura yuklandi."
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.loadingStatus = "Xatolik: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Decode Preview Image
    public func decodePreview(for entry: PVRTextureEntry, completion: @escaping (UIImage?) -> Void) {
        if let cached = entry.cachedPreview {
            completion(cached)
            return
        }
        
        guard let dURL = datURL else {
            completion(nil)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var chunkData: Data? = nil
            
            if (entry.isModified || entry.isNew), let mod = entry.modifiedChunk {
                chunkData = mod
            } else {
                do {
                    let handle = try FileHandle(forReadingFrom: dURL)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: UInt64(entry.offset))
                    
                    var readLen = Int(entry.size)
                    if readLen < 16 {
                        let headerData = handle.readData(ofLength: 16)
                        if headerData.count == 16 {
                            let csz = headerData[8..<12].withUnsafeBytes { $0.load(as: UInt32.self) }
                            readLen = Int(csz)
                            try handle.seek(toOffset: UInt64(entry.offset))
                        }
                    }
                    chunkData = handle.readData(ofLength: readLen)
                } catch {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
            }
            
            guard let chunk = chunkData, chunk.count >= 16 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let v0 = chunk.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
            let is4BPPByHeader = ((v0 >> 16) == 0x8C02)
            let is2BPPByHeader = ((v0 >> 16) == 0x8C01)
            
            let payloadBytes = chunk.count - 16
            let is2BPP: Bool
            if is4BPPByHeader {
                is2BPP = false
            } else if is2BPPByHeader {
                is2BPP = true
            } else if payloadBytes >= (entry.width * entry.height) / 2 {
                is2BPP = false
            } else {
                is2BPP = (entry.format == .pvrtc2bpp)
            }
            
            let payload = chunk.subdata(in: 16..<chunk.count)
            let mainMipBytes = max(32, (entry.width * entry.height) / (is2BPP ? 4 : 2))
            
            let slice = payload.prefix(mainMipBytes)
            let decoded = PVRTCDecompressor.decompress(
                data: Data(slice),
                width: entry.width,
                height: entry.height,
                is2BPP: is2BPP
            )
            
            DispatchQueue.main.async {
                entry.cachedPreview = decoded
                completion(decoded)
            }
        }
    }
    
    // MARK: - Add Texture
    public func addTexture(image: UIImage, name: String, is4BPP: Bool) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanName.isEmpty else { throw PVRError.compressionFailed }
        
        guard let encoded = PVRTCCompressor.encodeToWarDrumChunk(image: image, texName: cleanName, is4BPP: is4BPP) else {
            throw PVRError.compressionFailed
        }
        
        let mainMip = max(32, (encoded.width * encoded.height) / (is4BPP ? 2 : 4))
        let payload = encoded.chunk.subdata(in: 16..<encoded.chunk.count)
        let preview = PVRTCDecompressor.decompress(
            data: Data(payload.prefix(mainMip)),
            width: encoded.width,
            height: encoded.height,
            is2BPP: !is4BPP
        )
        
        if let existing = entries.first(where: { $0.name.lowercased() == cleanName }) {
            existing.width = encoded.width
            existing.height = encoded.height
            existing.format = is4BPP ? .pvrtc4bpp : .pvrtc2bpp
            existing.rawTxtLine = encoded.txtLine
            existing.size = UInt32(encoded.chunk.count)
            existing.modifiedChunk = encoded.chunk
            existing.cachedPreview = preview
            existing.isModified = true
        } else {
            let newIndex = entries.count + 1
            let entry = PVRTextureEntry(
                index: newIndex,
                name: cleanName,
                width: encoded.width,
                height: encoded.height,
                format: is4BPP ? .pvrtc4bpp : .pvrtc2bpp,
                offset: 0,
                size: UInt32(encoded.chunk.count),
                val0: 0,
                rawTxtLine: encoded.txtLine
            )
            entry.modifiedChunk = encoded.chunk
            entry.cachedPreview = preview
            entry.isModified = true
            entry.isNew = true
            entries.append(entry)
        }
        
        objectWillChange.send()
    }
    
    // MARK: - Replace Texture
    public func replaceTexture(entry: PVRTextureEntry, withImage image: UIImage, is4BPP: Bool? = nil) throws {
        let target4BPP = is4BPP ?? (entry.format == .pvrtc4bpp)
        try addTexture(image: image, name: entry.name, is4BPP: target4BPP)
    }
    
    // MARK: - Delete Texture
    public func deleteTexture(entry: PVRTextureEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries.remove(at: idx)
        objectWillChange.send()
    }
    
    // MARK: - Revert Texture
    public func revertTexture(entry: PVRTextureEntry) {
        if entry.isNew {
            deleteTexture(entry: entry)
            return
        }
        entry.isModified = false
        entry.modifiedChunk = nil
        entry.cachedPreview = nil
        objectWillChange.send()
    }
    
    // MARK: - Export Single Texture as PNG
    public func exportTextureAsPNG(entry: PVRTextureEntry, completion: @escaping (Result<URL, Error>) -> Void) {
        decodePreview(for: entry) { image in
            guard let img = image, let pngData = img.pngData() else {
                completion(.failure(PVRError.decompressionFailed))
                return
            }
            
            do {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PVR_Exports", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                let fileURL = tempDir.appendingPathComponent("\(entry.name).png")
                try pngData.write(to: fileURL, options: .atomic)
                completion(.success(fileURL))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Save Database (Clean rebuild of DAT, TOC, SZ, TXT)
    public func saveDatabase(progress: @escaping (Double) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let sourceDatURL = datURL, let sourceTocURL = tocURL else {
            completion(.failure(PVRError.fileNotFound))
            return
        }
        
        let currentEntries = self.entries
        let headerLine = self.txtHeaderLine
        let targetTxtURL = self.txtURL ?? sourceDatURL.deletingPathExtension().deletingPathExtension().appendingPathExtension("txt")
        let targetSzURL = self.szURL ?? sourceDatURL.deletingPathExtension().appendingPathExtension("sz")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("pvr_build_\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                
                let tempDat = tempDir.appendingPathComponent("temp.pvr.dat")
                let tempToc = tempDir.appendingPathComponent("temp.pvr.toc")
                let tempSz = tempDir.appendingPathComponent("temp.pvr.sz")
                let tempTxt = tempDir.appendingPathComponent("temp.txt")
                
                FileManager.default.createFile(atPath: tempDat.path, contents: nil, attributes: nil)
                let outDatHandle = try FileHandle(forWritingTo: tempDat)
                defer { try? outDatHandle.close() }
                
                let inDatHandle = try FileHandle(forReadingFrom: sourceDatURL)
                defer { try? inDatHandle.close() }
                
                let totalCount = currentEntries.count + 1
                var newToc = [UInt32](repeating: 0, count: totalCount)
                var newSz = [UInt32](repeating: 0, count: totalCount)
                
                var currentOffset: UInt32 = 0
                
                for (i, entry) in currentEntries.enumerated() {
                    let entryIdx = i + 1
                    var chunkData: Data
                    
                    if (entry.isModified || entry.isNew), let mod = entry.modifiedChunk {
                        chunkData = mod
                    } else {
                        try inDatHandle.seek(toOffset: UInt64(entry.offset))
                        chunkData = inDatHandle.readData(ofLength: Int(entry.size))
                    }
                    
                    let chunkLen = UInt32(chunkData.count)
                    newToc[entryIdx] = currentOffset
                    newSz[entryIdx] = chunkLen
                    
                    try outDatHandle.write(contentsOf: chunkData)
                    currentOffset += chunkLen
                    
                    // 16-byte alignment padding
                    let pad = (16 - (currentOffset % 16)) % 16
                    if pad > 0 {
                        try outDatHandle.write(contentsOf: Data(repeating: 0, count: Int(pad)))
                        currentOffset += pad
                    }
                    
                    if i % 100 == 0 || i == currentEntries.count - 1 {
                        let pct = 0.1 + (Double(i) / Double(currentEntries.count)) * 0.7
                        DispatchQueue.main.async { progress(pct) }
                    }
                }
                
                // TOC slot 0 holds total file size in War Drum format
                newToc[0] = currentOffset
                newSz[0] = currentOffset
                
                // Write TOC
                var tocBytes = Data(capacity: totalCount * 4)
                for val in newToc {
                    var le = val.littleEndian
                    tocBytes.append(Data(bytes: &le, count: 4))
                }
                try tocBytes.write(to: tempToc, options: .atomic)
                
                // Write SZ
                var szBytes = Data(capacity: totalCount * 4)
                for val in newSz {
                    var le = val.littleEndian
                    szBytes.append(Data(bytes: &le, count: 4))
                }
                try szBytes.write(to: tempSz, options: .atomic)
                
                // Write TXT
                var txtLines: [String] = [headerLine]
                for entry in currentEntries {
                    txtLines.append(entry.rawTxtLine)
                }
                let fullTxt = txtLines.joined(separator: "\r\n") + "\r\n"
                if let txtData = fullTxt.data(using: .isoLatin1) {
                    try txtData.write(to: tempTxt, options: .atomic)
                }
                
                DispatchQueue.main.async { progress(0.9) }
                
                // Atomically replace all files
                _ = try FileManager.default.replaceItemAt(sourceDatURL, withItemAt: tempDat)
                _ = try FileManager.default.replaceItemAt(sourceTocURL, withItemAt: tempToc)
                
                if FileManager.default.fileExists(atPath: targetSzURL.path) {
                    _ = try? FileManager.default.replaceItemAt(targetSzURL, withItemAt: tempSz)
                } else {
                    try? FileManager.default.moveItem(at: tempSz, to: targetSzURL)
                }
                
                if FileManager.default.fileExists(atPath: targetTxtURL.path) {
                    _ = try? FileManager.default.replaceItemAt(targetTxtURL, withItemAt: tempTxt)
                } else {
                    try? FileManager.default.moveItem(at: tempTxt, to: targetTxtURL)
                }
                
                DispatchQueue.main.async {
                    for i in 0..<currentEntries.count {
                        currentEntries[i].offset = newToc[i + 1]
                        currentEntries[i].size = newSz[i + 1]
                        currentEntries[i].isModified = false
                        currentEntries[i].isNew = false
                        currentEntries[i].modifiedChunk = nil
                    }
                    progress(1.0)
                    completion(.success(()))
                }
            } catch {
                try? FileManager.default.removeItem(at: tempDir)
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
