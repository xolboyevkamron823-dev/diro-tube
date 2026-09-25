import SwiftUI

struct ArchiveHeaderView: View {
    @ObservedObject var archive: IMGArchive
    let onOpen: () -> Void
    let onRebuild: () -> Void
    let onAdd: () -> Void
    let onGuide: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // App Title & Status
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.yellow)
                    
                    Text("IMG TOOL")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("iOS")
                        .font(.system(size: 11, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(6)
                }
                
                Spacer()
                
                Button(action: onGuide) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle.fill")
                        Text("Qo'llanma")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.95))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.0, green: 0.8, blue: 0.95).opacity(0.15))
                    .cornerRadius(20)
                }
            }
            
            // Archive Card
            VStack(alignment: .leading, spacing: 10) {
                if archive.isLoaded {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(archive.archiveName)
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundColor(.white)
                            
                            HStack(spacing: 8) {
                                Label(archive.archiveSizeFormatted, systemImage: "internaldrive.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.green)
                                
                                Text("•")
                                    .foregroundColor(.gray)
                                
                                Label("\(archive.entries.count) fayl", systemImage: "doc.on.doc.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: onOpen) {
                            Text("Boshqasini Ochish")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Quick Action Buttons Toolbar
                    HStack(spacing: 8) {
                        Button(action: onRebuild) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("Rebuild")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.purple.opacity(0.8))
                            .cornerRadius(8)
                        }
                        
                        Button(action: onAdd) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Fayl Qo'shish")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(8)
                        }
                    }
                } else {
                    // Empty state prompt
                    HStack(spacing: 14) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Arxiv Tanlanmagan")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text("GTA arxivini (.img) ochish uchun bosing")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Button(action: onOpen) {
                            Text("IMG Ochish")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.yellow)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(red: 0.12, green: 0.14, blue: 0.2))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
}
