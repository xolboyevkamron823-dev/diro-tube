import SwiftUI
import WebKit

struct DFFWebView: UIViewRepresentable {
    let dffBase64: String
    let fileName: String
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0)
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        
        if let htmlPath = Bundle.main.path(forResource: "dff_viewer", ofType: "html", inDirectory: "dff_preview") {
            let url = URL(fileURLWithPath: htmlPath)
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if let fallbackPath = Bundle.main.path(forResource: "dff_viewer", ofType: "html") {
            let url = URL(fileURLWithPath: fallbackPath)
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.isPageLoaded {
            context.coordinator.sendDFF(to: uiView, base64: dffBase64, name: fileName)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(dffBase64: dffBase64, fileName: fileName)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var isPageLoaded = false
        let dffBase64: String
        let fileName: String
        
        init(dffBase64: String, fileName: String) {
            self.dffBase64 = dffBase64
            self.fileName = fileName
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            sendDFF(to: webView, base64: dffBase64, name: fileName)
        }
        
        func sendDFF(to webView: WKWebView, base64: String, name: String) {
            let js = "window.loadDFFFromBase64 && window.loadDFFFromBase64('\(base64)', '\(name)');"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

struct DFFViewerSheet: View {
    let entry: IMGEntry
    let archive: IMGArchive
    @Environment(\.presentationMode) var presentationMode
    
    @State private var dffBase64: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var shareURL: URL? = nil
    @State private var showShareSheet: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.06, blue: 0.08).edgesIgnoringSafeArea(.all)
                
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(1.5)
                        Text("\(entry.name) model ma'lumotlari o'qilmoqda...")
                            .foregroundColor(.gray)
                            .font(.system(size: 15))
                    }
                } else if let err = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.red)
                        Text("3D Modelni ochishda xatolik:")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(err)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    DFFWebView(dffBase64: dffBase64, fileName: entry.name)
                }
            }
            .navigationBarTitle(Text(entry.name), displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Yopish")
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .semibold))
                },
                trailing: Button(action: {
                    exportFile()
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.blue)
                }
            )
            .onAppear {
                loadModelData()
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ActivityView(activityItems: [url])
                }
            }
        }
    }
    
    private func loadModelData() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try archive.extractData(for: entry)
                let base64 = data.base64EncodedString()
                DispatchQueue.main.async {
                    self.dffBase64 = base64
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func exportFile() {
        do {
            let url = try archive.extractToFile(entry: entry)
            self.shareURL = url
            self.showShareSheet = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
