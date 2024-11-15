import Vapor

struct TokenResponse: Content {
    let user: UserResponse
    let accessToken: String
    let refreshToken: String
}
