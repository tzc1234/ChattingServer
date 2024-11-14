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

extension UserDTO: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(3...))
        validations.add("password", as: String.self, is: .count(3...))
        validations.add("email", as: String.self, is: .email)
    }
}
