import SwiftUI
import UIKit
import PhotosUI

public struct PhotoPicker: UIViewControllerRepresentable {
    public let onPick: (UIImage, String) -> Void
    
    public init(onPick: @escaping (UIImage, String) -> Void) {
        self.onPick = onPick
    }
    
    public func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    public class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage, String) -> Void
        
        init(onPick: @escaping (UIImage, String) -> Void) {
            self.onPick = onPick
        }
        
        public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else { return }
            let suggestedName = results.first?.itemProvider.suggestedName ?? "texture"
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] (image, error) in
                    if let img = image as? UIImage {
                        DispatchQueue.main.async {
                            self?.onPick(img, suggestedName)
                        }
                    }
                }
            }
        }
    }
}
