import Vapor

struct TokenResponse: Content {
    let user: UserResponse
    let accessToken: String
    let refreshToken: String
    
    enum CodingKeys: String, CodingKey {
        case user = "user"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
