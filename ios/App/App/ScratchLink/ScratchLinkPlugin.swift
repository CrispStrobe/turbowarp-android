import Foundation
import Capacitor
import WebKit

private enum SLSessionType {
    case ble, bt

    init?(url: URL) {
        switch url.lastPathComponent {
        case "ble": self = .ble
        case "bt":  self = .bt
        default:    return nil
        }
    }
}

private struct SLMessage: Codable {
    let method: Method
    let socketId: Int
    let url: URL?
    let jsonrpc: String?

    enum Method: String, Codable {
        case open, close, send
    }
}

/// Capacitor plugin that intercepts Scratch Link WebSocket connections and
/// routes them to native CoreBluetooth (BLE) or ExternalAccessory (Classic BT).
@objc(ScratchLinkPlugin)
public class ScratchLinkPlugin: CAPPlugin {

    private var sessions = [Int: ScratchLinkSession]()

    // MARK: - Plugin lifecycle

    public override func load() {
        guard let jsURL = Bundle(for: ScratchLinkPlugin.self)
            .url(forResource: "inject-scratch-link", withExtension: "js"),
              let js = try? String(contentsOf: jsURL, encoding: .utf8) else {
            print("ScratchLinkPlugin: inject-scratch-link.js not found in bundle")
            return
        }

        // Inject into all frames (forMainFrameOnly: false) so it works when
        // the editor is loaded inside an iframe or after navigation.
        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.bridge?.webView?.configuration.userContentController.addUserScript(script)
            self.bridge?.webView?.configuration.userContentController.add(self, name: "scratchLink")
        }
    }
}

// MARK: - WKScriptMessageHandler

extension ScratchLinkPlugin: WKScriptMessageHandler {

    /// All WKScriptMessage callbacks arrive on the main thread.
    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        guard let jsonString = message.body as? String,
              let jsonData = jsonString.data(using: .utf8),
              let msg = try? JSONDecoder().decode(SLMessage.self, from: jsonData) else {
            return
        }

        let socketId = msg.socketId

        switch msg.method {
        case .open:
            guard let url = msg.url, let type = SLSessionType(url: url) else { return }
            do {
                try openSession(socketId: socketId, type: type)
            } catch {
                print("ScratchLinkPlugin: failed to open session: \(error)")
            }

        case .close:
            let session = sessions.removeValue(forKey: socketId)
            DispatchQueue.global(qos: .userInitiated).async {
                session?.sessionWasClosed()
            }

        case .send:
            guard let jsonrpc = msg.jsonrpc, let session = sessions[socketId] else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                session.didReceiveText(jsonrpc)
            }
        }
    }

    // Called on main thread — stores session in dict on same thread for safety.
    private func openSession(socketId: Int, type: SLSessionType) throws {
        let webSocket = ScratchWebSocket { [weak self] message in
            guard let self = self else { return }
            // JSON-encode the message string to avoid quote/backslash injection in JS
            let safeMsg: String
            if let data = try? JSONEncoder().encode(message),
               let str = String(data: data, encoding: .utf8) {
                safeMsg = str  // Already includes surrounding quotes: "..."
            } else {
                safeMsg = "\"\""
            }
            let js = """
                (function(){var s=ScratchLink.sockets.get(\(socketId));if(s)s.handleMessage(\(safeMsg));})();
                """
            DispatchQueue.main.async {
                self.bridge?.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        switch type {
        case .ble:
            sessions[socketId] = try BLESession(withSocket: webSocket)
        case .bt:
            sessions[socketId] = try BTSession(withSocket: webSocket)
        }
    }
}
