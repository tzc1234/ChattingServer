import Vapor

struct RefreshTokenDTO: Content {
    let token: String
    let user: UserDTO.Public
}
