import SwiftUI

struct RebuildSheet: View {
    @ObservedObject var archive: IMGArchive
    @Environment(\.presentationMode) var presentationMode
    
    @State private var progress: Double = 0.0
    @State private var isFinished: Bool = false
    @State private var errorText: String? = nil
    
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.12).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: isFinished ? "checkmark.circle.fill" : "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(isFinished ? .green : .purple)
                    
                    Text(isFinished ? "Rebuild Muvaffaqiyatli Tugadi!" : "Arxiv Defragmentatsiya Qilinmoqda")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text(isFinished ? "Keraksiz bo'shliqlar olib tashlandi, arxiv hajmi ixchamlashtirildi." : "Barcha fayllar yangi sektorlarga zichlashtirib yozilmoqda...")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                if let err = errorText {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                } else if !isFinished {
                    // Progress Bar
                    VStack(spacing: 8) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                            .scaleEffect(x: 1, y: 3, anchor: .center)
                            .cornerRadius(4)
                        
                        HStack {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(archive.entries.count) ta fayl qayta ishlanmoqda")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 30)
                }
                
                if isFinished {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Tugatish")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 30)
                }
            }
            .padding(24)
        }
        .onAppear {
            startRebuild()
        }
    }
    
    private func startRebuild() {
        archive.rebuildArchive(progress: { pct in
            self.progress = pct
        }) { result in
            switch result {
            case .success:
                self.progress = 1.0
                self.isFinished = true
            case .failure(let err):
                self.errorText = err.localizedDescription
            }
        }
    }
}
