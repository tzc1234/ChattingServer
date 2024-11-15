import Vapor

struct RefreshTokenDTO: Content {
    let token: String
    let user: UserResponse
}
