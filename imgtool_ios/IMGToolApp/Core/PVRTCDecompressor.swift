import Foundation
import UIKit
import CoreGraphics

public final class PVRTCDecompressor {
    
    @inline(__always)
    private static func shiftl16(_ x: inout UInt16, _ n: Int) -> UInt8 {
        let res = UInt8((x >> (16 - n)) & 0xFF)
        x = (x << n) & 0xFFFF
        return res
    }
    
    @inline(__always)
    private static func replicateTopBit(_ x: UInt8) -> UInt8 {
        return (x | (x >> 4)) & 0xFF
    }
    
    private static func unpack5554Colour(_ packedCol: UInt32, _ abColours: inout [[Int]]) {
        var rawBits: [UInt16] = [
            UInt16(packedCol & 0xFFFE),
            UInt16((packedCol >> 16) & 0xFFFF)
        ]
        
        for i in 0..<2 {
            var rawPixel = rawBits[i]
            let isOpaque = shiftl16(&rawPixel, 1)
            
            if isOpaque != 0 {
                let r = Int(shiftl16(&rawPixel, 5))
                let g = Int(shiftl16(&rawPixel, 5))
                let bShift = shiftl16(&rawPixel, 5)
                let b = Int((i == 0) ? replicateTopBit(bShift) : bShift)
                abColours[i] = [r, g, b, 0x0F]
            } else {
                var a = Int(shiftl16(&rawPixel, 3)) << 1
                var r = Int(replicateTopBit(shiftl16(&rawPixel, 4) << 1))
                var g = Int(replicateTopBit(shiftl16(&rawPixel, 4) << 1))
                var b = Int(shiftl16(&rawPixel, 4) << 1)
                if i == 0 {
                    b |= (b >> 3)
                } else {
                    b = Int(replicateTopBit(UInt8(b & 0xFF)))
                }
                abColours[i] = [r, g, b, a]
            }
        }
    }
    
    private static func unpackModulations(
        packedMod: UInt32,
        packedCol: UInt32,
        is2BPP: Bool,
        startX: Int,
        startY: Int,
        modVals: inout [[Int]],
        modModes: inout [[Int]]
    ) {
        let blockModMode = Int(packedCol & 1)
        var modBits = packedMod
        
        if is2BPP && blockModMode != 0 {
            for y in 0..<4 {
                for x in 0..<8 {
                    modModes[y + startY][x + startX] = blockModMode
                    if ((x ^ y) & 1) == 0 {
                        modVals[y + startY][x + startX] = Int(modBits & 3)
                        modBits >>= 2
                    }
                }
            }
        } else if is2BPP {
            for y in 0..<4 {
                for x in 0..<8 {
                    modModes[y + startY][x + startX] = blockModMode
                    modVals[y + startY][x + startX] = (modBits & 1) != 0 ? 0x3 : 0x0
                    modBits >>= 1
                }
            }
        } else {
            for y in 0..<4 {
                for x in 0..<4 {
                    modModes[y + startY][x + startX] = blockModMode
                    modVals[y + startY][x + startX] = Int(modBits & 3)
                    modBits >>= 2
                }
            }
        }
    }
    
    @inline(__always)
    private static func interpolateColours(
        _ cP: [Int],
        _ cQ: [Int],
        _ cR: [Int],
        _ cS: [Int],
        is2BPP: Bool,
        x: Int,
        y: Int,
        result: inout [Int]
    ) {
        var v = (y & 0x3) | ((~y & 0x2) << 1)
        var u: Int
        var uscale: Int
        
        if is2BPP {
            u = (x & 0x7) | ((~x & 0x4) << 1)
            u -= 4 // BLK_X_2BPP / 2
            uscale = 8
        } else {
            u = (x & 0x3) | ((~x & 0x2) << 1)
            u -= 2 // BLK_X_4BPP / 2
            uscale = 4
        }
        v -= 2 // BLK_Y_SIZE / 2
        
        for k in 0..<4 {
            let tmp1 = cP[k] * uscale + u * (cQ[k] - cP[k])
            let tmp2 = cR[k] * uscale + u * (cS[k] - cR[k])
            result[k] = tmp1 * 4 + v * (tmp2 - tmp1)
        }
        
        if is2BPP {
            result[0] >>= 2
            result[1] >>= 2
            result[2] >>= 2
            result[3] >>= 1
        } else {
            result[0] >>= 1
            result[1] >>= 1
            result[2] >>= 1
        }
        
        // 5554 to 8888 conversion
        result[0] += result[0] >> 5
        result[1] += result[1] >> 5
        result[2] += result[2] >> 5
        result[3] += result[3] >> 4
    }
    
    @inline(__always)
    private static func getModulationValue(
        x: Int,
        y: Int,
        is2BPP: Bool,
        modVals: [[Int]],
        modModes: [[Int]],
        doPT: inout Bool
    ) -> Int {
        let rep0: [Int] = [0, 3, 5, 8]
        let rep1: [Int] = [0, 4, 4, 8]
        
        let localY = (y & 0x3) | ((~y & 0x2) << 1)
        let localX = is2BPP ? ((x & 0x7) | ((~x & 0x4) << 1)) : ((x & 0x3) | ((~x & 0x2) << 1))
        
        let mode = modModes[localY][localX]
        let val = modVals[localY][localX]
        
        if mode == 0 {
            doPT = false
            return rep0[val]
        } else if is2BPP {
            doPT = false
            if ((localX ^ localY) & 1) == 0 {
                return rep0[val]
            } else if mode == 1 {
                return (rep0[modVals[localY - 1][localX]] +
                        rep0[modVals[localY + 1][localX]] +
                        rep0[modVals[localY][localX - 1]] +
                        rep0[modVals[localY][localX + 1]] + 2) / 4
            } else if mode == 2 {
                return (rep0[modVals[localY][localX - 1]] +
                        rep0[modVals[localY][localX + 1]] + 1) / 2
            } else {
                return (rep0[modVals[localY - 1][localX]] +
                        rep0[modVals[localY + 1][localX]] + 1) / 2
            }
        } else {
            doPT = (val == 2)
            return rep1[val]
        }
    }
    
    @inline(__always)
    private static func twiddleUV(ySize: UInt32, xSize: UInt32, yPos: UInt32, xPos: UInt32) -> UInt32 {
        let minDimension = (ySize < xSize) ? ySize : xSize
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
    
    public static func decompress(data: Data, width: Int, height: Int, is2BPP: Bool) -> UIImage? {
        guard width > 0 && height > 0 else { return nil }
        
        let blkXSize = is2BPP ? 8 : 4
        let blkYSize = 4
        let blkXDim = max(2, width / blkXSize)
        let blkYDim = max(2, height / blkYSize)
        
        let totalBlocks = blkXDim * blkYDim
        let expectedBytes = totalBlocks * 8
        guard data.count >= expectedBytes else { return nil }
        
        var words = [UInt32](repeating: 0, count: totalBlocks * 2)
        _ = words.withUnsafeMutableBytes { outBuf in
            data.copyBytes(to: outBuf, count: expectedBytes)
        }
        
        var outPixels = [UInt8](repeating: 255, count: width * height * 4)
        
        var prevBlocks: (Int, Int, Int, Int)? = nil
        var colours5554 = [[[Int]]](repeating: [[Int]](repeating: [0, 0, 0, 0], count: 2), count: 4)
        var modVals = [[Int]](repeating: [Int](repeating: 0, count: 16), count: 8)
        var modModes = [[Int]](repeating: [Int](repeating: 0, count: 16), count: 8)
        
        var colA = [Int](repeating: 0, count: 4)
        var colB = [Int](repeating: 0, count: 4)
        var tempAB = [[Int]](repeating: [0, 0, 0, 0], count: 2)
        
        outPixels.withUnsafeMutableBufferPointer { outPtr in
            for y in 0..<height {
                var blkY = (y - blkYSize / 2) % height
                if blkY < 0 { blkY += height }
                blkY /= blkYSize
                let blkYp1 = (blkY + 1) % blkYDim
                
                for x in 0..<width {
                    var blkX = (x - blkXSize / 2) % width
                    if blkX < 0 { blkX += width }
                    blkX /= blkXSize
                    let blkXp1 = (blkX + 1) % blkXDim
                    
                    let idx00 = Int(twiddleUV(ySize: UInt32(blkYDim), xSize: UInt32(blkXDim), yPos: UInt32(blkY), xPos: UInt32(blkX)))
                    let idx01 = Int(twiddleUV(ySize: UInt32(blkYDim), xSize: UInt32(blkXDim), yPos: UInt32(blkY), xPos: UInt32(blkXp1)))
                    let idx10 = Int(twiddleUV(ySize: UInt32(blkYDim), xSize: UInt32(blkXDim), yPos: UInt32(blkYp1), xPos: UInt32(blkX)))
                    let idx11 = Int(twiddleUV(ySize: UInt32(blkYDim), xSize: UInt32(blkXDim), yPos: UInt32(blkYp1), xPos: UInt32(blkXp1)))
                    
                    let needsUpdate: Bool
                    if let prev = prevBlocks {
                        needsUpdate = (prev.0 != idx00 || prev.1 != idx01 || prev.2 != idx10 || prev.3 != idx11)
                    } else {
                        needsUpdate = true
                    }
                    
                    if needsUpdate {
                        let quadIndices = [idx00, idx01, idx10, idx11]
                        var startY = 0
                        for row in 0..<2 {
                            var startX = 0
                            for col in 0..<2 {
                                let blkIdx = quadIndices[row * 2 + col]
                                let pMod = words[blkIdx * 2]
                                let pCol = words[blkIdx * 2 + 1]
                                
                                unpack5554Colour(pCol, &tempAB)
                                colours5554[row * 2 + col] = tempAB
                                
                                unpackModulations(
                                    packedMod: pMod,
                                    packedCol: pCol,
                                    is2BPP: is2BPP,
                                    startX: startX,
                                    startY: startY,
                                    modVals: &modVals,
                                    modModes: &modModes
                                )
                                startX += blkXSize
                            }
                            startY += blkYSize
                        }
                        prevBlocks = (idx00, idx01, idx10, idx11)
                    }
                    
                    interpolateColours(
                        colours5554[0][0],
                        colours5554[1][0],
                        colours5554[2][0],
                        colours5554[3][0],
                        is2BPP: is2BPP,
                        x: x,
                        y: y,
                        result: &colA
                    )
                    
                    interpolateColours(
                        colours5554[0][1],
                        colours5554[1][1],
                        colours5554[2][1],
                        colours5554[3][1],
                        is2BPP: is2BPP,
                        x: x,
                        y: y,
                        result: &colB
                    )
                    
                    var doPT = false
                    let mod = getModulationValue(
                        x: x,
                        y: y,
                        is2BPP: is2BPP,
                        modVals: modVals,
                        modModes: modModes,
                        doPT: &doPT
                    )
                    
                    let r = colA[0] + ((mod * (colB[0] - colA[0])) >> 3)
                    let g = colA[1] + ((mod * (colB[1] - colA[1])) >> 3)
                    let b = colA[2] + ((mod * (colB[2] - colA[2])) >> 3)
                    let a = doPT ? 0 : (colA[3] + ((mod * (colB[3] - colA[3])) >> 3))
                    
                    let pos = (y * width + x) * 4
                    outPtr[pos + 0] = UInt8(clamping: r)
                    outPtr[pos + 1] = UInt8(clamping: g)
                    outPtr[pos + 2] = UInt8(clamping: b)
                    outPtr[pos + 3] = UInt8(clamping: a)
                }
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(outPixels) as CFData),
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
