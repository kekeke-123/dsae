import SwiftUI
import UniformTypeIdentifiers

/// 「文件」App 的导入 / 导出选择器封装。
struct DocumentPicker: UIViewControllerRepresentable {

    enum Mode {
        case importing
        case importingFolder
        case exporting([URL])
    }

    let mode: Mode
    var completion: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        switch mode {
        case .importing:
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
            picker.allowsMultipleSelection = false
        case .importingFolder:
            // 文件夹要原地读写，asCopy 对目录不适用。
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            picker.allowsMultipleSelection = false
        case .exporting(let urls):
            picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.completion(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.completion(nil)
        }
    }
}
