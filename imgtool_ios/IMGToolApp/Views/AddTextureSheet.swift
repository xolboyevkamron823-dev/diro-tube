import SwiftUI
import UniformTypeIdentifiers

public struct AddTextureSheet: View {
    @ObservedObject var database: PVRDatabase
    @Binding var isPresented: Bool
    let onComplete: (String) -> Void
    
    @State private var selectedImage: UIImage? = nil
    @State private var textureName: String = ""
    @State private var selectedFormat: PVRFormat = .pvrtc2bpp
    @State private var resolutionOption: String = "Avtomatik"
    
    @State private var showPhotoPicker: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    
    let resolutionOptions = ["Avtomatik", "128 × 128", "256 × 256", "512 × 512", "1024 × 1024"]
    
    var existingMatch: PVRTextureEntry? {
        let clean = textureName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return nil }
        return database.entries.first { $0.name.lowercased() == clean }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12).edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Image Picker Card
                        VStack(spacing: 12) {
                            if let img = selectedImage {
                                ZStack {
                                    CheckerboardBackground(size: 8)
                                        .frame(height: 180)
                                        .cornerRadius(12)
                                    
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 170)
                                        .cornerRadius(8)
                                }
                                .padding(.horizontal, 4)
                                
                                HStack(spacing: 12) {
                                    Button(action: { showPhotoPicker = true }) {
                                        HStack {
                                            Image(systemName: "photo.on.rectangle.angled")
                                            Text("Rasmlardan")
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color(red: 0.18, green: 0.22, blue: 0.28))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                    
                                    Button(action: { showFilePicker = true }) {
                                        HStack {
                                            Image(systemName: "folder")
                                            Text("Fayllardan")
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color(red: 0.18, green: 0.22, blue: 0.28))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                }
                            } else {
                                VStack(spacing: 14) {
                                    Image(systemName: "square.and.arrow.down.on.square")
                                        .font(.system(size: 40))
                                        .foregroundColor(.appCyan)
                                    
                                    Text("Rasm faylini tanlang (PNG yoki JPG)")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    HStack(spacing: 12) {
                                        Button(action: { showPhotoPicker = true }) {
                                            HStack {
                                                Image(systemName: "photo.on.rectangle.angled")
                                                Text("Fotogalereyadan")
                                            }
                                            .font(.system(size: 13, weight: .bold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                        }
                                        
                                        Button(action: { showFilePicker = true }) {
                                            HStack {
                                                Image(systemName: "folder.fill")
                                                Text("Files ilovasidan")
                                            }
                                            .font(.system(size: 13, weight: .bold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(Color(red: 0.2, green: 0.25, blue: 0.32))
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // Texture Name Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tekstura Nomi (GTA modelidagi nom):")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.gray)
                            
                            TextField("Masalan: infernus_wheel, vehiclegrunge256...", text: $textureName)
                                .font(.system(size: 15, design: .monospaced))
                                .padding(12)
                                .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            
                            if let match = existingMatch {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(.orange)
                                    Text("Bu nomdagi tekstura mavjud (#{match.index}). Uning o'rniga almashtiriladi (Replace).")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.orange)
                                }
                            } else if !textureName.isEmpty {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Yangi noyob tekstura sifatida bazaga qo'shiladi.")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Format Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Siqish Formati (PVRTC):")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.gray)
                            
                            Picker("Format", selection: $selectedFormat) {
                                Text("PVRTC 2BPP (Tezkor, GTA standarti)").tag(PVRFormat.pvrtc2bpp)
                                Text("PVRTC 4BPP (Yuqori Sifat / HD)").tag(PVRFormat.pvrtc4bpp)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        .padding(.horizontal)
                        
                        // Resolution Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("O'lcham (Resolution):")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.gray)
                            
                            Picker("Resolution", selection: $resolutionOption) {
                                ForEach(resolutionOptions, id: \.self) { opt in
                                    Text(opt).tag(opt)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        .padding(.horizontal)
                        
                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }
                        
                        // Confirm Button
                        Button(action: processAdd) {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .padding(.trailing, 6)
                                    Text("PVRTC-ga siqilmoqda...")
                                } else {
                                    Image(systemName: existingMatch != nil ? "arrow.triangle.2.circlepath" : "plus.circle.fill")
                                    Text(existingMatch != nil ? "Almashtirish (Replace)" : "Bazaga Qo'shish (Add)")
                                }
                            }
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isCanSubmit ? Color.green : Color.gray.opacity(0.3))
                            .foregroundColor(isCanSubmit ? .black : .gray)
                            .cornerRadius(10)
                        }
                        .disabled(!isCanSubmit || isProcessing)
                        .padding(.horizontal)
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitle("Yangi Tekstura Qo'shish", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Bekor Qilish") {
                    isPresented = false
                }
                .foregroundColor(.gray)
            )
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker { image, name in
                    self.selectedImage = image
                    if self.textureName.isEmpty {
                        self.textureName = name.lowercased()
                            .replacingOccurrences(of: " ", with: "_")
                            .replacingOccurrences(of: ".png", with: "")
                            .replacingOccurrences(of: ".jpg", with: "")
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker(contentTypes: [.png, .jpeg, .image]) { url in
                    var access = false
                    if url.startAccessingSecurityScopedResource() { access = true }
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    
                    if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                        self.selectedImage = img
                        if self.textureName.isEmpty {
                            let base = url.deletingPathExtension().lastPathComponent.lowercased()
                            self.textureName = base.replacingOccurrences(of: " ", with: "_")
                        }
                    }
                }
            }
        }
    }
    
    private var isCanSubmit: Bool {
        selectedImage != nil && !textureName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func processAdd() {
        guard let img = selectedImage else { return }
        let cleanName = textureName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanName.isEmpty else { return }
        
        isProcessing = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Apply target resolution if not auto
            var finalImage = img
            if resolutionOption != "Avtomatik" {
                let dims = resolutionOption.components(separatedBy: " × ")
                if dims.count == 2, let w = Int(dims[0]), let h = Int(dims[1]) {
                    if let resizedPixels = PVRTCCompressor.resizeImage(img, targetWidth: w, targetHeight: h) {
                        let colorSpace = CGColorSpaceCreateDeviceRGB()
                        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                        if let provider = CGDataProvider(data: Data(resizedPixels) as CFData),
                           let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                            finalImage = UIImage(cgImage: cg)
                        }
                    }
                }
            }
            
            do {
                try database.addTexture(
                    image: finalImage,
                    name: cleanName,
                    is4BPP: selectedFormat == .pvrtc4bpp
                )
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.isPresented = false
                    self.onComplete(cleanName)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
}
