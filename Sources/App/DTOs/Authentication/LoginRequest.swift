import Vapor

struct LoginRequest: Content {
    let email: String
    let password: String
}
