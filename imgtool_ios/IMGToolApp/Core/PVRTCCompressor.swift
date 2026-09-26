import Foundation
import UIKit
import CoreGraphics

public final class PVRTCCompressor {
    
    public static func nearestPOT(_ val: Int) -> Int {
        var p = 1
        while p < val { p *= 2 }
        if (p - val) < (val - p / 2) {
            return min(2048, max(16, p))
        } else {
            return min(2048, max(16, p / 2))
        }
    }
    
    private static func twiddleUV(ySize: UInt32, xSize: UInt32, yPos: UInt32, xPos: UInt32) -> UInt32 {
        let minDimension = min(ySize, xSize)
        var maxValue = (ySize < xSize) ? xPos : yPos
        var srcBitPos: UInt32 = 1
        var dstBitPos: UInt32 = 1
        var twiddled: UInt32 = 0
        var shiftCount: UInt32 = 0
        
        while srcBitPos < minDimension {
            if (yPos & srcBitPos) != 0 { twiddled |= dstBitPos }
            if (xPos & srcBitPos) != 0 { twiddled |= (dstBitPos << 1) }
            srcBitPos <<= 1
            dstBitPos <<= 2
            shiftCount += 1
        }
        maxValue >>= shiftCount
        twiddled |= (maxValue << (2 * shiftCount))
        return twiddled
    }
    
    private static func colorToRGB555(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt16 {
        let r5 = (UInt16(r) >> 3) & 0x1F
        let g5 = (UInt16(g) >> 3) & 0x1F
        let b5 = (UInt16(b) >> 3) & 0x1F
        return (1 << 15) | (r5 << 10) | (g5 << 5) | b5
    }
    
    private static func colorToRGBA4444(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> UInt16 {
        let a4 = (UInt16(a) >> 4) & 0x0F
        let r4 = (UInt16(r) >> 4) & 0x0F
        let g4 = (UInt16(g) >> 4) & 0x0F
        let b4 = (UInt16(b) >> 4) & 0x0F
        return (a4 << 12) | (r4 << 8) | (g4 << 4) | b4
    }
    
    public static func resizeImage(_ image: UIImage, targetWidth: Int, targetHeight: Int) -> [UInt8]? {
        let size = CGSize(width: targetWidth, height: targetHeight)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        guard let resized = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImage = resized.cgImage else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()
        
        var pixelData = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: &pixelData,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return pixelData
    }
    
    public static func encodeSingleLevel(pixels: [UInt8], width: Int, height: Int, is2BPP: Bool) -> Data {
        let blockXSize = is2BPP ? 8 : 4
        let blockYSize = 4
        let numBx = max(2, width / blockXSize)
        let numBy = max(2, height / blockYSize)
        let totalBlocks = numBx * numBy
        
        var blockColorsA = [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)](repeating: (0, 0, 0, 255), count: totalBlocks)
        var blockColorsB = [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)](repeating: (0, 0, 0, 255), count: totalBlocks)
        
        // Pass 1: compute min/max endpoints per block
        for by in 0..<numBy {
            for bx in 0..<numBx {
                let blkIdx = by * numBx + bx
                var minR: UInt8 = 255, minG: UInt8 = 255, minB: UInt8 = 255, minA: UInt8 = 255
                var maxR: UInt8 = 0, maxG: UInt8 = 0, maxB: UInt8 = 0, maxA: UInt8 = 0
                
                for dy in 0..<blockYSize {
                    let py = min(height - 1, by * blockYSize + dy)
                    for dx in 0..<blockXSize {
                        let px = min(width - 1, bx * blockXSize + dx)
                        let offset = (py * width + px) * 4
                        let r = pixels[offset]
                        let g = pixels[offset + 1]
                        let b = pixels[offset + 2]
                        let a = pixels[offset + 3]
                        
                        if r < minR { minR = r }
                        if g < minG { minG = g }
                        if b < minB { minB = b }
                        if a < minA { minA = a }
                        
                        if r > maxR { maxR = r }
                        if g > maxG { maxG = g }
                        if b > maxB { maxB = b }
                        if a > maxA { maxA = a }
                    }
                }
                
                blockColorsA[blkIdx] = (minR, minG, minB, minA)
                blockColorsB[blkIdx] = (maxR, maxG, maxB, maxA)
            }
        }
        
        var resultBlocks = Data(count: totalBlocks * 8)
        
        // Pass 2: assign modulations and store in Twiddle order
        resultBlocks.withUnsafeMutableBytes { (rawPtr: UnsafeMutableRawBufferPointer) in
            let u32Ptr = rawPtr.bindMemory(to: UInt32.self)
            
            for by in 0..<numBy {
                for bx in 0..<numBx {
                    let blkIdx = by * numBx + bx
                    let colA = blockColorsA[blkIdx]
                    let colB = blockColorsB[blkIdx]
                    
                    let colA16: UInt16
                    let colB16: UInt16
                    if colA.a < 250 || colB.a < 250 {
                        colA16 = colorToRGBA4444(colA.r, colA.g, colA.b, colA.a)
                        colB16 = colorToRGBA4444(colB.r, colB.g, colB.b, colB.a)
                    } else {
                        colA16 = colorToRGB555(colA.r, colA.g, colA.b)
                        colB16 = colorToRGB555(colB.r, colB.g, colB.b)
                    }
                    
                    var modWord: UInt32 = 0
                    
                    let pal: [(r: Int, g: Int, b: Int, a: Int)] = [
                        (Int(colA.r), Int(colA.g), Int(colA.b), Int(colA.a)),
                        (Int(colA.r) * 5 / 8 + Int(colB.r) * 3 / 8,
                         Int(colA.g) * 5 / 8 + Int(colB.g) * 3 / 8,
                         Int(colA.b) * 5 / 8 + Int(colB.b) * 3 / 8,
                         Int(colA.a) * 5 / 8 + Int(colB.a) * 3 / 8),
                        (Int(colA.r) * 3 / 8 + Int(colB.r) * 5 / 8,
                         Int(colA.g) * 3 / 8 + Int(colB.g) * 5 / 8,
                         Int(colA.b) * 3 / 8 + Int(colB.b) * 5 / 8,
                         Int(colA.a) * 3 / 8 + Int(colB.a) * 5 / 8),
                        (Int(colB.r), Int(colB.g), Int(colB.b), Int(colB.a))
                    ]
                    
                    for dy in 0..<blockYSize {
                        let py = min(height - 1, by * blockYSize + dy)
                        for dx in 0..<blockXSize {
                            let px = min(width - 1, bx * blockXSize + dx)
                            let pixOffset = (py * width + px) * 4
                            let pr = Int(pixels[pixOffset])
                            let pg = Int(pixels[pixOffset + 1])
                            let pb = Int(pixels[pixOffset + 2])
                            let pa = Int(pixels[pixOffset + 3])
                            
                            var bestIdx: UInt32 = 0
                            var bestDist = Int.max
                            
                            for (pIdx, pColor) in pal.enumerated() {
                                let dr = pr - pColor.r
                                let dg = pg - pColor.g
                                let db = pb - pColor.b
                                let da = pa - pColor.a
                                let dist = dr * dr + dg * dg + db * db + da * da
                                if dist < bestDist {
                                    bestDist = dist
                                    bestIdx = UInt32(pIdx)
                                }
                            }
                            
                            let pixelIndex = dy * blockXSize + dx
                            let shift = pixelIndex * (is2BPP ? 1 : 2)
                            let modVal = is2BPP ? (bestIdx >= 2 ? 1 : 0) : bestIdx
                            modWord |= (modVal << shift)
                        }
                    }
                    
                    let highWord = (UInt32(colB16) << 16) | (UInt32(colA16) << 1) | 0
                    let twiddledIndex = Int(twiddleUV(ySize: UInt32(numBy), xSize: UInt32(numBx), yPos: UInt32(by), xPos: UInt32(bx)))
                    
                    u32Ptr[twiddledIndex * 2] = modWord
                    u32Ptr[twiddledIndex * 2 + 1] = highWord
                }
            }
        }
        
        return resultBlocks
    }
    
    public static func crc32(_ string: String) -> UInt32 {
        guard let data = string.data(using: .latin1) else { return 0 }
        return crc32Data(data)
    }
    
    public static func crc32Data(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = (crc & 1) != 0 ? UInt32(0xEDB88320) : 0
                crc = (crc >> 1) ^ mask
            }
        }
        return ~crc
    }
    
    public static func encodeToWarDrumChunk(image: UIImage, texName: String, is4BPP: Bool) -> (chunk: Data, width: Int, height: Int, txtLine: String)? {
        let origW = Int(image.size.width)
        let origH = Int(image.size.height)
        let targetW = nearestPOT(origW)
        let targetH = nearestPOT(origH)
        
        // 1. Build mipmap pyramid from smallest to largest
        var mipLevels: [(w: Int, h: Int, data: Data)] = []
        
        var curW = targetW
        var curH = targetH
        var pyramidSizes: [(w: Int, h: Int)] = []
        
        while curW >= 8 && curH >= 8 {
            pyramidSizes.append((curW, curH))
            if curW == 8 && curH == 8 { break }
            curW = max(8, curW / 2)
            curH = max(8, curH / 2)
        }
        
        // Encode each level
        for sz in pyramidSizes {
            guard let px = resizeImage(image, targetWidth: sz.w, targetHeight: sz.h) else { return nil }
            let encoded = encodeSingleLevel(pixels: px, width: sz.w, height: sz.h, is2BPP: !is4BPP)
            mipLevels.append((sz.w, sz.h, encoded))
        }
        
        // War Drum stores mipmaps from smallest to largest
        var payload = Data()
        for level in mipLevels.reversed() {
            payload.append(level.data)
        }
        
        // Add 16-byte War Drum Header
        // val0 = (0x8c020000 if 4bpp else 0x8c010000) | (crc32(name) & 0xffff)
        let baseVal: UInt32 = is4BPP ? 0x8C020000 : 0x8C010000
        let nameCrc = crc32(texName) & 0xFFFF
        let val0 = baseVal | nameCrc
        
        let chunkSz = UInt32(16 + payload.count)
        let hFlag = UInt16(targetH | 0x8000)
        
        var header = Data()
        var v0 = val0.littleEndian
        var w = UInt16(targetW).littleEndian
        var h = hFlag.littleEndian
        var csz = chunkSz.littleEndian
        var extra: UInt32 = 0
        
        header.append(Data(bytes: &v0, count: 4))
        header.append(Data(bytes: &w, count: 2))
        header.append(Data(bytes: &h, count: 2))
        header.append(Data(bytes: &csz, count: 4))
        header.append(Data(bytes: &extra, count: 4))
        
        var fullChunk = header
        fullChunk.append(payload)
        
        // Generate gta3.txt metadata line
        let pngHash = String(format: "%08x", crc32(texName))
        let imgHash = String(format: "%08x", crc32Data(payload))
        let fmtTag = is4BPP ? " format=3" : ""
        let txtLine = "\"\(texName)\" width=\(targetW) height=\(targetH) png=\(pngHash) img=\(imgHash)\(fmtTag)"
        
        return (fullChunk, targetW, targetH, txtLine)
    }
}
