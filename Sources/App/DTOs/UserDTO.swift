import Fluent
import Vapor

struct UserDTO: Content {
    let id: UUID?
    let name: String
    let email: String
    let password: String
    
    func toModel() -> User {
        let model = User()
        model.id = id
        model.name = name
        model.email = email
        model.password = password
        return model
    }
}
