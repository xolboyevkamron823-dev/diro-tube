import UIKit
import WebKit
import UniformTypeIdentifiers

class ViewController: UIViewController, WKScriptMessageHandler, UIDocumentPickerDelegate {
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
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "_allowUniversalAccessFromFileURLs")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadLocalApp() {
        guard let bundlePath = Bundle.main.path(forResource: "www", ofType: nil) else {
            // Fallback to bundle root if www is flat
            if let htmlPath = Bundle.main.path(forResource: "index", ofType: "html") {
                let htmlUrl = URL(fileURLWithPath: htmlPath)
                webView.loadFileURL(htmlUrl, allowingReadAccessTo: htmlUrl.deletingLastPathComponent())
            }
            return
        }

        let wwwUrl = URL(fileURLWithPath: bundlePath)
        let indexUrl = wwwUrl.appendingPathComponent("index.html")

        if FileManager.default.fileExists(atPath: indexUrl.path) {
            webView.loadFileURL(indexUrl, allowingReadAccessTo: wwwUrl)
        }
    }

    private var currentPickerMode: String = "open"

    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "openDocumentPicker" {
            let mode = (message.body as? [String: Any])?["mode"] as? String ?? "open"
            openDocumentPicker(mode: mode)
        } else if message.name == "exportDFF" {
            guard let dict = message.body as? [String: Any],
                  let base64 = dict["base64Data"] as? String,
                  let fileName = dict["fileName"] as? String else { return }
            exportDFFFile(base64: base64, fileName: fileName)
        }
    }

    // MARK: - Native Document Picker
    private func openDocumentPicker(mode: String) {
        self.currentPickerMode = mode
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .item], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.data", "public.item"], in: .import)
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let selectedUrl = urls.first else { return }

        do {
            let data = try Data(contentsOf: selectedUrl)
            let base64 = data.base64EncodedString()
            let fileName = selectedUrl.lastPathComponent

            let js = "window.onNativeFileOpened('\(base64)', '\(fileName)', '\(self.currentPickerMode)');"
            webView.evaluateJavaScript(js, completionHandler: nil)

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            let alert = UIAlertController(title: "Xatolik", message: "Faylni o'qishda xato: \(error.localizedDescription)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
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
