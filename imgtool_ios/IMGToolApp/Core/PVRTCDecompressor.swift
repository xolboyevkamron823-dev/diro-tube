import Foundation
import UIKit
import CoreGraphics

public final class PVRTCDecompressor {
    
    private struct AMTCBlock {
        var modBits: UInt32
        var colBits: UInt32
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
    
    private static func unpackColor(packed: UInt32, colors: inout [[Int]]) {
        let rawBits: [UInt16] = [
            UInt16(packed & 0xFFFE),
            UInt16(packed >> 16)
        ]
        
        for i in 0..<2 {
            var raw = rawBits[i]
            let isOpaque = (raw >> 15) & 1
            raw <<= 1
            
            if isOpaque != 0 {
                let r = Int(raw >> 11) & 0x1F
                let g = Int(raw >> 6) & 0x1F
                let b = Int(raw >> 1) & 0x1F
                // Scale 5-bit to 8-bit
                colors[i][0] = (r << 3) | (r >> 2)
                colors[i][1] = (g << 3) | (g >> 2)
                colors[i][2] = (b << 3) | (b >> 2)
                colors[i][3] = 255
            } else {
                let a = Int(raw >> 12) & 0x07
                let r = Int(raw >> 8) & 0x0F
                let g = Int(raw >> 4) & 0x0F
                let b = Int(raw) & 0x0F
                // Scale 4-bit/3-bit to 8-bit
                colors[i][0] = (r << 4) | r
                colors[i][1] = (g << 4) | g
                colors[i][2] = (b << 4) | b
                colors[i][3] = (a << 5) | (a << 2) | (a >> 1)
            }
        }
    }
    
    public static func decompress(data: Data, width: Int, height: Int, is2BPP: Bool) -> UIImage? {
        guard width > 0 && height > 0 else { return nil }
        
        let blockXSize = is2BPP ? 8 : 4
        let blockYSize = 4
        let blkXDim = max(2, width / blockXSize)
        let blkYDim = max(2, height / blockYSize)
        
        let totalBlocks = blkXDim * blkYDim
        let expectedBytes = totalBlocks * 8
        guard data.count >= expectedBytes else { return nil }
        
        var blocks = [AMTCBlock](repeating: AMTCBlock(modBits: 0, colBits: 0), count: totalBlocks)
        data.withUnsafeBytes { rawPtr in
            let u32Ptr = rawPtr.bindMemory(to: UInt32.self)
            for i in 0..<totalBlocks {
                blocks[i] = AMTCBlock(modBits: u32Ptr[i * 2], colBits: u32Ptr[i * 2 + 1])
            }
        }
        
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        
        // Cache unpacked colors per block to avoid re-unpacking
        var blockColors = [[[Int]]](repeating: [[Int]](repeating: [0, 0, 0, 255], count: 2), count: totalBlocks)
        for i in 0..<totalBlocks {
            unpackColor(packed: blocks[i].colBits, colors: &blockColors[i])
        }
        
        let modWeights: [[Double]] = [
            [1.0, 0.0],           // 0: 8/8 A, 0/8 B
            [5.0 / 8.0, 3.0 / 8.0], // 1: 5/8 A, 3/8 B
            [3.0 / 8.0, 5.0 / 8.0], // 2: 3/8 A, 5/8 B
            [0.0, 1.0]            // 3: 0/8 A, 8/8 B
        ]
        
        for y in 0..<height {
            let by0 = ((y - blockYSize / 2) + height) % height / blockYSize
            let by1 = (by0 + 1) % blkYDim
            let v = (Double(y % blockYSize) + 0.5) / Double(blockYSize)
            
            for x in 0..<width {
                let bx0 = ((x - blockXSize / 2) + width) % width / blockXSize
                let bx1 = (bx0 + 1) % blkXDim
                let u = (Double(x % blockXSize) + 0.5) / Double(blockXSize)
                
                // Get 4 block twiddled indices
                let idx00 = Int(twiddleUV(ySize: UInt32(blkYDim), xSize: UInt32(blkXDim), yPos: UInt32(by0), xPos: UInt32(bx0)))
                let idx01 = Int(twiddleUV(ySize: UInt32(blkYDim), xSize: UInt32(blkXDim), yPos: UInt32(by0), xPos: UInt32(bx1)))
                let idx10 = Int(twiddleUV(ySize: UInt32(blkYDim), xSize: UInt32(blkXDim), yPos: UInt32(by1), xPos: UInt32(bx0)))
                let idx11 = Int(twiddleUV(ySize: UInt32(blkYDim), xSize: UInt32(blkXDim), yPos: UInt32(by1), xPos: UInt32(bx1)))
                
                // Bilinear interpolation weights
                let w00 = (1.0 - u) * (1.0 - v)
                let w01 = u * (1.0 - v)
                let w10 = (1.0 - u) * v
                let w11 = u * v
                
                // Interpolated Color A
                let colA00 = blockColors[idx00][0]
                let colA01 = blockColors[idx01][0]
                let colA10 = blockColors[idx10][0]
                let colA11 = blockColors[idx11][0]
                
                let aR = Double(colA00[0]) * w00 + Double(colA01[0]) * w01 + Double(colA10[0]) * w10 + Double(colA11[0]) * w11
                let aG = Double(colA00[1]) * w00 + Double(colA01[1]) * w01 + Double(colA10[1]) * w10 + Double(colA11[1]) * w11
                let aB = Double(colA00[2]) * w00 + Double(colA01[2]) * w01 + Double(colA10[2]) * w10 + Double(colA11[2]) * w11
                let aA = Double(colA00[3]) * w00 + Double(colA01[3]) * w01 + Double(colA10[3]) * w10 + Double(colA11[3]) * w11
                
                // Interpolated Color B
                let colB00 = blockColors[idx00][1]
                let colB01 = blockColors[idx01][1]
                let colB10 = blockColors[idx10][1]
                let colB11 = blockColors[idx11][1]
                
                let bR = Double(colB00[0]) * w00 + Double(colB01[0]) * w01 + Double(colB10[0]) * w10 + Double(colB11[0]) * w11
                let bG = Double(colB00[1]) * w00 + Double(colB01[1]) * w01 + Double(colB10[1]) * w10 + Double(colB11[1]) * w11
                let bB = Double(colB00[2]) * w00 + Double(colB01[2]) * w01 + Double(colB10[2]) * w10 + Double(colB11[2]) * w11
                let bA = Double(colB00[3]) * w00 + Double(colB01[3]) * w01 + Double(colB10[3]) * w10 + Double(colB11[3]) * w11
                
                // Get modulation index for pixel from parent block
                let currBx = x / blockXSize
                let currBy = y / blockYSize
                let currIdx = Int(twiddleUV(ySize: UInt32(blkYDim), xSize: UInt32(blkXDim), yPos: UInt32(currBy), xPos: UInt32(currBx)))
                let modBits = blocks[currIdx].modBits
                
                let localX = x % blockXSize
                let localY = y % blockYSize
                let bitShift = (localY * blockXSize + localX) * (is2BPP ? 1 : 2)
                let modIndex = is2BPP ? ((Int(modBits >> bitShift) & 1) != 0 ? 3 : 0) : (Int(modBits >> bitShift) & 3)
                
                let weights = modWeights[modIndex]
                let r = UInt8(clamping: Int(aR * weights[0] + bR * weights[1]))
                let g = UInt8(clamping: Int(aG * weights[0] + bG * weights[1]))
                let b = UInt8(clamping: Int(aB * weights[0] + bB * weights[1]))
                let a = UInt8(clamping: Int(aA * weights[0] + bA * weights[1]))
                
                let pixelOffset = (y * width + x) * 4
                rgba[pixelOffset] = r
                rgba[pixelOffset + 1] = g
                rgba[pixelOffset + 2] = b
                rgba[pixelOffset + 3] = a
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}
