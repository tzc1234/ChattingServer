import Vapor

struct UserWithTokenResponse: Content {
    let user: UserResponse
    let accessToken: String
    let refreshToken: String
}
