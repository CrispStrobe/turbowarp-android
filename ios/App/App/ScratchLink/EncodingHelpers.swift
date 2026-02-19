import Foundation

class EncodingHelpers {

    public static func decodeBuffer(fromJSON json: [String: Any]) throws -> Data {
        guard let message = json["message"] as? String else {
            throw JSONRPCError.invalidParams(data: "missing message property")
        }
        let encoding = json["encoding"] as? String

        switch encoding {
        case .some("base64"):
            if let result = Data(base64Encoded: message) {
                return result
            } else {
                throw JSONRPCError.invalidParams(data: "failed to decode Base64 message")
            }
        case .none:
            if let result = message.data(using: .utf8) {
                return result
            } else {
                throw JSONRPCError.internalError(data: "failed to transcode message to UTF-8")
            }
        default:
            throw JSONRPCError.invalidParams(data: "unsupported encoding: \(encoding!)")
        }
    }

    public static func encodeBuffer(
            _ data: Data, withEncoding encoding: String?, intoObject destination: [String: Any]? = nil)
                    -> [String: Any]? {
        var result = destination ?? [:]

        switch encoding {
        case .some("base64"):
            result["encoding"] = "base64"
            result["message"] = data.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
        case .none:
            result.removeValue(forKey: "encoding")
            result["message"] = String.init(data: data, encoding: String.Encoding.utf8)
        default:
            return nil
        }

        return result
    }
}
