import Foundation

struct ErrorResponse: Codable {
    let error: Bool
    let reason: String
}
