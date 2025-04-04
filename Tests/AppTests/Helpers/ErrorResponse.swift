import Foundation
import XCTVapor

struct ErrorResponse: Codable {
    let error: Bool
    let reason: String
}

func errorReason(from response: XCTHTTPResponse) throws -> String {
    let error = try response.content.decode(ErrorResponse.self)
    return error.reason
}
