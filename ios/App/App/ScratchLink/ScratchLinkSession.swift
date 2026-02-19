import Foundation

enum SerializationError: Error {
    case invalid(String)
    case internalError(String)
}

class ScratchLinkSession {
    private let NetworkProtocolVersion: String = "1.2"

    typealias RequestID = Int
    typealias JSONRPCCompletionHandler = (_ result: Any?, _ error: JSONRPCError?) -> Void

    let socketProtocol: String? = nil
    private let webSocket: ScratchWebSocket
    private var nextId: RequestID = 0
    private var completionHandlers = [RequestID: JSONRPCCompletionHandler]()

    private let socketWriteSemaphore = DispatchSemaphore(value: 1)
    private let sessionSemaphore = DispatchSemaphore(value: 1)

    required init(withSocket webSocket: ScratchWebSocket) throws {
        self.webSocket = webSocket
    }

    func sessionWasClosed() {
        self.sessionSemaphore.mutex {
            if completionHandlers.count > 0 {
                print("ScratchLinkSession: session closed with \(completionHandlers.count) pending requests")
                for (_, completionHandler) in completionHandlers {
                    completionHandler(nil, JSONRPCError.internalError(data: "Session closed"))
                }
            }
            self.webSocket.close()
        }
    }

    func didReceiveText(_ text: String) {
        guard let messageData = text.data(using: .utf8) else {
            print("ScratchLinkSession: failed to convert text to UTF-8")
            return
        }
        sessionSemaphore.wait()
        didReceiveData(messageData) { jsonResponseData in
            self.sessionSemaphore.signal()

            if let jsonResponseData = jsonResponseData {
                if let jsonResponseText = String(data: jsonResponseData, encoding: .utf8) {
                    self.socketWriteSemaphore.wait()
                    self.webSocket.sendStringMessage(string: jsonResponseText, final: true) {
                        self.socketWriteSemaphore.signal()
                    }
                } else {
                    print("ScratchLinkSession: failed to decode response")
                }
            }
        }
    }

    func didReceiveCall(_ method: String, withParams params: [String: Any],
                        completion: @escaping JSONRPCCompletionHandler) throws {
        switch method {
        case "pingMe":
            completion("willPing", nil)
            sendRemoteRequest("ping") { (result: Any?, _: JSONRPCError?) in
                print("ScratchLinkSession: ping result:", String(describing: result))
            }
        case "getVersion":
            completion(getVersion(), nil)
        default:
            throw JSONRPCError.methodNotFound(data: method)
        }
    }

    func getVersion() -> [String: String] {
        return ["protocol": NetworkProtocolVersion]
    }

    func sendRemoteRequest(_ method: String, withParams params: [String: Any]? = nil,
                           completion: JSONRPCCompletionHandler? = nil) {
        var request: [String: Any?] = [
            "jsonrpc": "2.0",
            "method": method
        ]

        if params != nil {
            request["params"] = params
        }

        if completion != nil {
            let requestId = getNextId()
            completionHandlers[requestId] = completion
            request["id"] = requestId
        }

        do {
            let requestData = try JSONSerialization.data(withJSONObject: request)
            guard let requestText = String(data: requestData, encoding: .utf8) else {
                throw SerializationError.internalError("Could not serialize request before sending to client")
            }
            self.socketWriteSemaphore.wait()
            self.webSocket.sendStringMessage(string: requestText, final: true) {
                self.socketWriteSemaphore.signal()
            }
        } catch {
            print("ScratchLinkSession: error serializing request: \(error)")
        }
    }

    func sendErrorNotification(_ error: JSONRPCError) throws {
        let message = makeResponse(forId: NSNull(), nil, error)
        let messageData = try JSONSerialization.data(withJSONObject: message)
        guard let messageText = String(data: messageData, encoding: .utf8) else {
            throw SerializationError.internalError("Could not serialize error before sending to client")
        }
        self.socketWriteSemaphore.wait()
        self.webSocket.sendStringMessage(string: messageText, final: true) {
            self.socketWriteSemaphore.signal()
        }
    }

    func makeResponse(forId responseId: Any, _ result: Any?, _ error: JSONRPCError?) -> [String: Any] {
        var response: [String: Any] = ["jsonrpc": "2.0"]
        response["id"] = responseId
        if let error = error {
            var jsonError: [String: Any] = [
                "code": error.code,
                "message": error.message
            ]
            if let data = error.data {
                jsonError["data"] = data
            }
            response["error"] = jsonError
        } else {
            response["result"] = result ?? NSNull()
        }
        return response
    }

    func didReceiveData(_ data: Data, completion: @escaping (_ jsonResponseData: Data?) -> Void) {
        var responseId: Any = NSNull()

        func sendResponse(_ result: Any?, _ error: JSONRPCError?) {
            do {
                let response = makeResponse(forId: responseId, result, error)
                let jsonData = try JSONSerialization.data(withJSONObject: response)
                completion(jsonData)
            } catch let firstError {
                do {
                    let errorResponse = makeResponse(forId: responseId, nil, JSONRPCError(
                            code: 2, message: "Could not encode response", data: String(describing: firstError)))
                    let jsonData = try JSONSerialization.data(withJSONObject: errorResponse)
                    completion(jsonData)
                } catch {
                    print("ScratchLinkSession: failed to report encoding failure")
                    completion(nil)
                }
            }
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw JSONRPCError.parseError(data: "unrecognized message structure")
            }

            responseId = json["id"] ?? NSNull()

            if json["jsonrpc"] as? String != "2.0" {
                throw JSONRPCError.invalidRequest(data: "unrecognized JSON-RPC version string")
            }

            if json.keys.contains("method") {
                try didReceiveRequest(json, completion: sendResponse)
            } else if json.keys.contains("result") || json.keys.contains("error") {
                try didReceiveResponse(json)
                completion(nil)
            } else {
                throw JSONRPCError.invalidRequest(data: "message is neither request nor response")
            }
        } catch let error where error is JSONRPCError {
            sendResponse(nil, error as? JSONRPCError)
        } catch {
            sendResponse(nil, JSONRPCError(
                    code: 1, message: "Unhandled error during call", data: String(describing: error)))
        }
    }

    func didReceiveRequest(_ json: [String: Any], completion: @escaping JSONRPCCompletionHandler) throws {
        guard let method = json["method"] as? String else {
            throw JSONRPCError.invalidRequest(data: "method value missing or not a string")
        }
        let params: [String: Any] = (json["params"] as? [String: Any]) ?? [String: Any]()
        try didReceiveCall(method, withParams: params, completion: completion)
    }

    func didReceiveResponse(_ json: [String: Any]) throws {
        guard let requestId = json["id"] as? RequestID else {
            throw JSONRPCError.invalidRequest(data: "response ID value missing or wrong type")
        }
        guard let completionHandler = completionHandlers.removeValue(forKey: requestId) else {
            throw JSONRPCError.invalidRequest(data: "response ID does not correspond to any open request")
        }
        if let errorJSON = json["error"] as? [String: Any] {
            completionHandler(nil, JSONRPCError(fromJSON: errorJSON))
        } else {
            let rawResult = json["result"]
            completionHandler((rawResult is NSNull ? nil : rawResult), nil)
        }
    }

    private func getNextId() -> RequestID {
        let result = self.nextId
        self.nextId += 1
        return result
    }
}
