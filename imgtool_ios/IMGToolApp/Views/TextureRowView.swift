import SwiftUI

public struct TextureRowView: View {
    @ObservedObject var entry: PVRTextureEntry
    let database: PVRDatabase
    let onSelect: () -> Void
    
    @State private var thumbnail: UIImage? = nil
    
    public init(entry: PVRTextureEntry, database: PVRDatabase, onSelect: @escaping () -> Void) {
        self.entry = entry
        self.database = database
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Texture Thumbnail
                ZStack {
                    CheckerboardBackground(size: 6)
                        .frame(width: 50, height: 50)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    
                    if let img = thumbnail ?? entry.cachedPreview {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .cornerRadius(6)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 50, height: 50)
                
                // Name and Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if entry.isNew {
                            Text("YANGI")
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.black)
                                .cornerRadius(4)
                        } else if entry.isModified {
                            Text("O'ZGARTIRILGAN")
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow)
                                .foregroundColor(.black)
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(entry.dimensionsString)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Text("•")
                            .foregroundColor(.gray.opacity(0.6))
                        
                        Text(entry.format.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(entry.format == .pvrtc4bpp ? .appCyan : .orange)
                        
                        Text("•")
                            .foregroundColor(.gray.opacity(0.6))
                        
                        Text(entry.sizeString)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(red: 0.1, green: 0.12, blue: 0.16))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        if entry.cachedPreview != nil {
            self.thumbnail = entry.cachedPreview
            return
        }
        database.decodePreview(for: entry) { img in
            self.thumbnail = img
        }
    }
}

// Background checkerboard pattern to visualize transparency (iOS 14+ compatible)
public struct CheckerboardBackground: View {
    let size: CGFloat
    
    public init(size: CGFloat = 8) {
        self.size = size
    }
    
    public var body: some View {
        GeometryReader { geometry in
            Path { path in
                let cols = Int(geometry.size.width / size) + 1
                let rows = Int(geometry.size.height / size) + 1
                
                for r in 0..<rows {
                    for c in 0..<cols {
                        if (r + c) % 2 == 0 {
                            let rect = CGRect(
                                x: CGFloat(c) * size,
                                y: CGFloat(r) * size,
                                width: size,
                                height: size
                            )
                            path.addRect(rect)
                        }
                    }
                }
            }
            .fill(Color(white: 0.18))
            .background(Color(white: 0.12))
        }
    }
}
