import Vapor

struct UserResponse: Content {
    let id: Int?
    let name: String
    let email: String
    let avatar: String?
}
