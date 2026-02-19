import Capacitor
import UIKit
import UniformTypeIdentifiers

/// iOS equivalent of the Android FileSavePlugin.
/// Provides native file open/save dialogs backed by UIDocumentPickerViewController.
/// The JS bridge (tw-capacitor-file-bridge.js) accesses this as window.Capacitor.Plugins.FileSave.
@objc(FileSavePlugin)
public class FileSavePlugin: CAPPlugin, UIDocumentPickerDelegate {

    private var currentCall: CAPPluginCall?
    private var isSaveMode: Bool = false
    private var tempFileURL: URL?

    // MARK: - Plugin methods

    /// Open ACTION_CREATE_DOCUMENT equivalent: let the user choose where to save a file.
    /// Expected call params: { fileName: string, mimeType: string, data: base64string }
    /// Resolves: { uri: string }
    @objc func saveFile(_ call: CAPPluginCall) {
        let fileName = call.getString("fileName") ?? "project.sb3"

        guard let base64String = call.getString("data"),
              let data = Data(base64Encoded: base64String) else {
            call.reject("No data provided or invalid base64")
            return
        }

        // Write to a temporary file so the picker can export it
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            call.reject("Failed to write temp file: \(error.localizedDescription)")
            return
        }

        self.currentCall = call
        self.isSaveMode = true
        self.tempFileURL = fileURL

        DispatchQueue.main.async {
            let picker: UIDocumentPickerViewController
            if #available(iOS 14.0, *) {
                picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
            } else {
                picker = UIDocumentPickerViewController(url: fileURL, in: .exportToService)
            }
            picker.delegate = self
            self.bridge?.viewController?.present(picker, animated: true, completion: nil)
        }
    }

    /// Open ACTION_OPEN_DOCUMENT equivalent: let the user pick a file to load.
    /// Expected call params: { mimeType?: string }
    /// Resolves: { data: base64string, name: string, uri: string }
    @objc func openFile(_ call: CAPPluginCall) {
        self.currentCall = call
        self.isSaveMode = false
        self.tempFileURL = nil

        DispatchQueue.main.async {
            let picker: UIDocumentPickerViewController
            if #available(iOS 14.0, *) {
                // asCopy: true gives us our own copy we can read without security scoping worries
                picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            } else {
                picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .open)
            }
            picker.delegate = self
            picker.allowsMultipleSelection = false
            self.bridge?.viewController?.present(picker, animated: true, completion: nil)
        }
    }

    // MARK: - UIDocumentPickerDelegate

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let call = currentCall else { return }
        currentCall = nil

        if isSaveMode {
            // The picker exported the file; just return the destination URI.
            if let tempURL = tempFileURL {
                try? FileManager.default.removeItem(at: tempURL)
                tempFileURL = nil
            }
            guard let url = urls.first else {
                call.reject("No destination URL returned")
                return
            }
            call.resolve(["uri": url.absoluteString])
        } else {
            // The picker gave us a copy of the file; read it and return base64.
            guard let url = urls.first else {
                call.reject("No file selected")
                return
            }
            // asCopy: true means no security-scoped resource access is needed,
            // but guard against older iOS just in case.
            let stopAccess = url.startAccessingSecurityScopedResource()
            defer { if stopAccess { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                call.resolve([
                    "data": data.base64EncodedString(),
                    "name": url.lastPathComponent,
                    "uri": url.absoluteString
                ])
            } catch {
                call.reject("Failed to read file: \(error.localizedDescription)")
            }
        }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard let call = currentCall else { return }
        currentCall = nil
        if isSaveMode, let tempURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempFileURL = nil
        }
        // Match the Android plugin's rejection code so JS cancel-detection works
        call.reject("User cancelled", "CANCELLED")
    }
}
