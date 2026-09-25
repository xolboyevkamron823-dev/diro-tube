import UIKit
import WebKit
import UniformTypeIdentifiers

class ViewController: UIViewController, WKScriptMessageHandler, UIDocumentPickerDelegate, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!

    override var prefersStatusBarHidden: Bool {
        return false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 15/255.0, green: 17/255.0, blue: 23/255.0, alpha: 1.0)

        setupWebView()
        loadLocalApp()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Register native bridge handlers
        contentController.add(self, name: "openDocumentPicker")
        contentController.add(self, name: "exportDFF")

        config.userContentController = contentController

        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = webpagePreferences

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = UIColor(red: 15/255.0, green: 17/255.0, blue: 23/255.0, alpha: 1.0)
        webView.isOpaque = true
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.uiDelegate = self

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadLocalApp() {
        let bundleUrl = Bundle.main.bundleURL

        let candidatePaths: [URL] = [
            bundleUrl.appendingPathComponent("index.html"),
            bundleUrl.appendingPathComponent("www").appendingPathComponent("index.html"),
            Bundle.main.url(forResource: "index", withExtension: "html") as Any,
            Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") as Any
        ].compactMap { $0 as? URL }

        for url in candidatePaths {
            if FileManager.default.fileExists(atPath: url.path) {
                print("Loading 3D Studio from: \(url.path)")
                do {
                    let htmlString = try String(contentsOf: url, encoding: .utf8)
                    let baseURL = url.deletingLastPathComponent()
                    webView.loadHTMLString(htmlString, baseURL: baseURL)
                    return
                } catch {
                    print("loadHTMLString failed: \(error), fallback to loadFileURL")
                    webView.loadFileURL(url, allowingReadAccessTo: bundleUrl)
                    return
                }
            }
        }

        let emergencyHTML = """
        <!DOCTYPE html><html><body style="background:#0f1117;color:#f87171;font-family:-apple-system,sans-serif;padding:30px;text-align:center;">
        <h2>Diro 3D Studio</h2>
        <p style="color:#f87171;">index.html topilmadi!</p>
        <p style="color:#94a3b8;font-size:12px;">\(bundleUrl.path)</p>
        </body></html>
        """
        webView.loadHTMLString(emergencyHTML, baseURL: nil)
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showErrorAlert(title: "Yuklash xatoligi", message: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showErrorAlert(title: "Yuklash xatoligi (Provisional)", message: error.localizedDescription)
    }

    // MARK: - WKUIDelegate
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "Diro 3D", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler() }))
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "Diro 3D", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ha", style: .default, handler: { _ in completionHandler(true) }))
        alert.addAction(UIAlertAction(title: "Yo'q", style: .cancel, handler: { _ in completionHandler(false) }))
        present(alert, animated: true)
    }

    private var currentPickerMode: String = "open"

    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "openDocumentPicker" {
            let mode = (message.body as? [String: Any])?["mode"] as? String ?? "open"
            DispatchQueue.main.async { [weak self] in
                self?.openDocumentPicker(mode: mode)
            }
        } else if message.name == "exportDFF" {
            guard let dict = message.body as? [String: Any],
                  let base64 = dict["base64Data"] as? String,
                  let fileName = dict["fileName"] as? String else { return }
            DispatchQueue.main.async { [weak self] in
                self?.exportDFFFile(base64: base64, fileName: fileName)
            }
        }
    }

    // MARK: - Native Document Picker: Select ANY file, including .dff and .txd
    private func openDocumentPicker(mode: String) {
        self.currentPickerMode = mode
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            var types: [UTType] = [
                .item,
                .data,
                .content,
                .image,
                .png,
                .jpeg
            ]
            if let dff = UTType("com.renderware.dff") { types.append(dff) }
            if let txd = UTType("com.renderware.txd") { types.append(txd) }
            if let dffExt = UTType(filenameExtension: "dff") { types.append(dffExt) }
            if let txdExt = UTType(filenameExtension: "txd") { types.append(txdExt) }

            picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: [
                "com.renderware.dff",
                "com.renderware.txd",
                "public.item",
                "public.data",
                "public.content",
                "public.image"
            ], in: .import)
        }
        picker.delegate = self
        picker.allowsMultipleSelection = true
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }

        // Sort so .dff is loaded first, then .txd, then images
        let sortedUrls = urls.sorted { a, b in
            let extA = a.pathExtension.lowercased()
            let extB = b.pathExtension.lowercased()
            if extA == "dff" { return true }
            if extB == "dff" { return false }
            if extA == "txd" { return true }
            return false
        }

        for selectedUrl in sortedUrls {
            sendFileToWebView(url: selectedUrl, mode: self.currentPickerMode)
        }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    // Handle incoming URL from AirDrop / Files app / Telegram "Open in"
    func handleIncomingURL(_ url: URL) {
        let mode = url.pathExtension.lowercased() == "txd" ? "txd" : "open"
        sendFileToWebView(url: url, mode: mode)
    }

    private func sendFileToWebView(url: URL, mode: String) {
        let needSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            let base64 = data.base64EncodedString()
            let fileName = url.lastPathComponent

            if base64.count < 3 * 1024 * 1024 {
                // Direct transfer for smaller files
                let payload: [String: String] = [
                    "data": base64,
                    "fileName": fileName,
                    "mode": mode
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    DispatchQueue.main.async { [weak self] in
                        self?.webView.evaluateJavaScript("window.onNativeFileJson(\(jsonStr));", completionHandler: nil)
                    }
                }
            } else {
                // Chunked transfer for large 34MB+ models to prevent WebKit IPC overflow
                let chunkSize = 512 * 1024 // 512KB per chunk
                let totalLength = base64.count
                let totalChunks = Int(ceil(Double(totalLength) / Double(chunkSize)))

                let initPayload: [String: Any] = [
                    "fileName": fileName,
                    "mode": mode,
                    "totalChunks": totalChunks
                ]
                if let initData = try? JSONSerialization.data(withJSONObject: initPayload),
                   let initJsonStr = String(data: initData, encoding: .utf8) {
                    DispatchQueue.main.async { [weak self] in
                        self?.webView.evaluateJavaScript("window.initNativeFileTransfer(\(initJsonStr));") { [weak self] _, _ in
                            self?.sendChunks(base64: base64, chunkSize: chunkSize, offset: 0, chunkIndex: 0)
                        }
                    }
                }
            }
        } catch {
            print("Error reading \(url): \(error)")
        }
    }

    private func sendChunks(base64: String, chunkSize: Int, offset: Int, chunkIndex: Int) {
        let totalLength = base64.count
        if offset >= totalLength {
            DispatchQueue.main.async { [weak self] in
                self?.webView.evaluateJavaScript("window.finishNativeFileTransfer();", completionHandler: nil)
            }
            return
        }

        let start = base64.index(base64.startIndex, offsetBy: offset)
        let nextOffset = min(offset + chunkSize, totalLength)
        let end = base64.index(base64.startIndex, offsetBy: nextOffset)
        let chunk = String(base64[start..<end])

        let chunkPayload: [String: Any] = ["chunk": chunk, "index": chunkIndex]
        if let chunkData = try? JSONSerialization.data(withJSONObject: chunkPayload),
           let chunkJsonStr = String(data: chunkData, encoding: .utf8) {
            DispatchQueue.main.async { [weak self] in
                self?.webView.evaluateJavaScript("window.appendNativeFileChunk(\(chunkJsonStr));") { [weak self] _, error in
                    if error == nil {
                        self?.sendChunks(base64: base64, chunkSize: chunkSize, offset: nextOffset, chunkIndex: chunkIndex + 1)
                    } else {
                        print("Error sending chunk \(chunkIndex): \(String(describing: error))")
                    }
                }
            }
        }
    }

    private func exportDFFFile(base64: String, fileName: String) {
        guard let data = Data(base64Encoded: base64) else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileUrl = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileUrl)

            let activityVC = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            present(activityVC, animated: true)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } catch {
            let alert = UIAlertController(title: "Xatolik", message: "Faylni saqlashda xato: \(error.localizedDescription)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}
