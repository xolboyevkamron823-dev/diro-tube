import SwiftUI

struct EntryRowView: View {
    let entry: IMGEntry
    let onView3D: (IMGEntry) -> Void
    let onReplace: (IMGEntry) -> Void
    let onExtract: (IMGEntry) -> Void
    let onDelete: (IMGEntry) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(entry.entryType.color.opacity(0.18))
                    .frame(width: 42, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(entry.entryType.color.opacity(0.35), lineWidth: 1)
                    )
                
                Image(systemName: entry.entryType.iconName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(entry.entryType.color)
            }
            
            // Name and details
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(entry.formattedSize)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.6, green: 0.65, blue: 0.75))
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    
                    Text("\(entry.sectors) sektor")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 8) {
                // 3D Preview button (only for DFF)
                if entry.isDFF {
                    Button(action: {
                        onView3D(entry)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "cube.fill")
                                .font(.system(size: 12))
                            Text("3D")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Replace button
                Button(action: {
                    onReplace(entry)
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                        .frame(width: 32, height: 32)
                        .background(Color.orange.opacity(0.18))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Context Menu for Extra Actions
                Menu {
                    Button(action: {
                        onExtract(entry)
                    }) {
                        Label("Fayllarga Saqlash (Extract)", systemImage: "square.and.arrow.up")
                    }
                    
                    if entry.isDFF {
                        Button(action: {
                            onView3D(entry)
                        }) {
                            Label("3D Modelda Ko'rish", systemImage: "eye.fill")
                        }
                    }
                    
                    Button(action: {
                        onReplace(entry)
                    }) {
                        Label("Almashtirish (Replace)", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        onDelete(entry)
                    }) {
                        Label("O'chirish (Delete)", systemImage: "trash.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 28, height: 32)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Color(red: 0.1, green: 0.12, blue: 0.16))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
