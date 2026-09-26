import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct DocumentPicker: UIViewControllerRepresentable {
    public let contentTypes: [UTType]
    public let allowsMultipleSelection: Bool
    public let asCopy: Bool
    public let onPickMultiple: (([URL]) -> Void)?
    public let onPickSingle: ((URL) -> Void)?
    
    public init(contentTypes: [UTType], allowsMultipleSelection: Bool = false, asCopy: Bool = false, onPick: @escaping (URL) -> Void) {
        self.contentTypes = contentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.asCopy = asCopy
        self.onPickSingle = onPick
        self.onPickMultiple = nil
    }
    
    public init(contentTypes: [UTType], allowsMultipleSelection: Bool = true, asCopy: Bool = false, onPickMultiple: @escaping ([URL]) -> Void) {
        self.contentTypes = contentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.asCopy = asCopy
        self.onPickSingle = nil
        self.onPickMultiple = onPickMultiple
    }
    
    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: asCopy)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else { return }
            
            if let multipleCallback = parent.onPickMultiple {
                multipleCallback(urls)
            } else if let singleCallback = parent.onPickSingle, let first = urls.first {
                singleCallback(first)
            }
        }
    }
}

public struct ActivityView: UIViewControllerRepresentable {
    public let activityItems: [Any]
    public let applicationActivities: [UIActivity]? = nil
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
