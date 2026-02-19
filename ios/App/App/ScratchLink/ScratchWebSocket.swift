import Foundation

/// Simple callback-based "WebSocket" shim used by ScratchLinkSession.
/// Instead of a real network socket, outgoing messages call the provided callback,
/// which delivers the message to JavaScript via WKWebView.evaluateJavaScript.
class ScratchWebSocket {

    let callback: (String) -> Void

    init(callback: @escaping (String) -> Void) {
        self.callback = callback
    }

    func readStringMessage(continuation: @escaping (String?, _ opcode: Any, _ final: Bool) -> Void) {
        // Not used in the Capacitor approach — messages arrive via WKScriptMessageHandler
    }

    func sendStringMessage(string: String, final: Bool, completion: @escaping () -> Void) {
        self.callback(string)
        completion()
    }

    func close() {
        // No real socket to close
    }
}
