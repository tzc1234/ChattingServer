import Vapor

struct TokenDTO: Content {
    let value: String
    let user: User
}
