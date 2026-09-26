import SwiftUI
import UniformTypeIdentifiers

public struct TextureDetailSheet: View {
    @ObservedObject var entry: PVRTextureEntry
    @ObservedObject var database: PVRDatabase
    @Binding var isPresented: Bool
    let onToast: (String, Bool) -> Void
    
    @State private var displayImage: UIImage? = nil
    @State private var isLoadingImage: Bool = true
    @State private var showPhotoReplacePicker: Bool = false
    @State private var showFileReplacePicker: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var shareURL: URL? = nil
    @State private var isProcessing: Bool = false
    @State private var showDeleteConfirm: Bool = false
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12).edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Preview Canvas with Checkerboard Background
                    ZStack {
                        CheckerboardBackground(size: 10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        if let img = displayImage {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(16)
                        } else if isLoadingImage {
                            ProgressView("Tekstura ochilmoqda...")
                                .foregroundColor(.white)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 32))
                                    .foregroundColor(.orange)
                                Text("Teksturani ochib bo'lmadi")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .frame(height: 280)
                    .background(Color.black)
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            // Metadata Card
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(entry.name)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    if entry.isNew {
                                        Text("YANGI")
                                            .font(.system(size: 11, weight: .black))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.green)
                                            .foregroundColor(.black)
                                            .cornerRadius(6)
                                    } else if entry.isModified {
                                        Text("O'ZGARTIRILGAN")
                                            .font(.system(size: 11, weight: .black))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.yellow)
                                            .foregroundColor(.black)
                                            .cornerRadius(6)
                                    }
                                }
                                
                                Divider().background(Color.white.opacity(0.1))
                                
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    MetaRow(label: "Indeks", value: "#\(entry.index)")
                                    MetaRow(label: "O'lchami", value: entry.dimensionsString)
                                    MetaRow(label: "Formati", value: "PVRTC \(entry.format.rawValue)")
                                    MetaRow(label: "Hajmi", value: entry.sizeString)
                                    MetaRow(label: "Offset", value: String(format: "0x%08X", entry.offset))
                                    MetaRow(label: "Holati", value: entry.isNew ? "Yangi qo'shilgan" : (entry.isModified ? "Yangilangan" : "Asl nusxa"))
                                }
                            }
                            .padding(14)
                            .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .padding(.top, 14)
                            
                            // Action Buttons Grid
                            VStack(spacing: 10) {
                                HStack(spacing: 10) {
                                    // Replace from Photos
                                    Button(action: { showPhotoReplacePicker = true }) {
                                        HStack {
                                            Image(systemName: "photo")
                                            Text("Rasmlardan Almashtirish")
                                        }
                                        .font(.system(size: 13, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                    
                                    // Replace from Files
                                    Button(action: { showFileReplacePicker = true }) {
                                        HStack {
                                            Image(systemName: "folder")
                                            Text("Fayllardan Almashtirish")
                                        }
                                        .font(.system(size: 13, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(red: 0.18, green: 0.22, blue: 0.3))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                }
                                
                                HStack(spacing: 10) {
                                    // Export PNG
                                    Button(action: exportPNG) {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("PNG Eksport Qilish")
                                        }
                                        .font(.system(size: 13, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(red: 0.14, green: 0.18, blue: 0.24))
                                        .foregroundColor(.cyan)
                                        .cornerRadius(8)
                                    }
                                    
                                    // Revert button if modified
                                    if entry.isModified || entry.isNew {
                                        Button(action: revertTexture) {
                                            HStack {
                                                Image(systemName: "arrow.counterclockwise")
                                                Text("Asliga Qaytarish")
                                            }
                                            .font(.system(size: 13, weight: .bold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.orange.opacity(0.2))
                                            .foregroundColor(.orange)
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                
                                // Delete Texture
                                Button(action: { showDeleteConfirm = true }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Teksturani O'chirish")
                                    }
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.15))
                                    .foregroundColor(.red)
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitle(entry.name, displayMode: .inline)
            .navigationBarItems(
                trailing: Button("Yopish") {
                    isPresented = false
                }
                .foregroundColor(.white)
            )
            .onAppear {
                loadImage()
            }
            .sheet(isPresented: $showPhotoReplacePicker) {
                PhotoPicker { newImg, _ in
                    replaceWithImage(newImg)
                }
            }
            .sheet(isPresented: $showFileReplacePicker) {
                DocumentPicker(contentTypes: [.png, .jpeg, .image]) { url in
                    var access = false
                    if url.startAccessingSecurityScopedResource() { access = true }
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    
                    if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                        replaceWithImage(img)
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let u = shareURL {
                    ActivityView(activityItems: [u])
                }
            }
            .alert(isPresented: $showDeleteConfirm) {
                Alert(
                    title: Text("Teksturani o'chirish"),
                    message: Text("'\(entry.name)' teksturasi bazadan olib tashlansinmi?"),
                    primaryButton: .destructive(Text("O'chirish")) {
                        database.deleteTexture(entry: entry)
                        isPresented = false
                        onToast("'\(entry.name)' o'chirildi", false)
                    },
                    secondaryButton: .cancel(Text("Bekor qilish"))
                )
            }
        }
    }
    
    private func loadImage() {
        if let cached = entry.cachedPreview {
            self.displayImage = cached
            self.isLoadingImage = false
            return
        }
        
        database.decodePreview(for: entry) { img in
            self.displayImage = img
            self.isLoadingImage = false
        }
    }
    
    private func replaceWithImage(_ newImg: UIImage) {
        isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try database.replaceTexture(entry: entry, withImage: newImg)
                DispatchQueue.main.async {
                    self.displayImage = newImg
                    self.isProcessing = false
                    self.onToast("'\(entry.name)' muvaffaqiyatli almashtirildi!", false)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.onToast("Xatolik: \(error.localizedDescription)", true)
                }
            }
        }
    }
    
    private func revertTexture() {
        database.revertTexture(entry: entry)
        self.displayImage = nil
        self.isLoadingImage = true
        loadImage()
        onToast("'\(entry.name)' asl holatiga qaytarildi", false)
    }
    
    private func exportPNG() {
        database.exportTextureAsPNG(entry: entry) { result in
            switch result {
            case .success(let url):
                self.shareURL = url
                self.showShareSheet = true
            case .failure(let error):
                self.onToast("Eksport xatosi: \(error.localizedDescription)", true)
            }
        }
    }
}

private struct MetaRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}
