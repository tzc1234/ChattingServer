import Vapor

struct RegisterResponse: Content {
    let user: UserResponse
    let accessToken: String
    let refreshToken: String
}
