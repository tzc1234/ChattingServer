import Vapor

struct TokenDTO: Content {
    let tokenValue: String
    let user: UserDTO.Public
}
