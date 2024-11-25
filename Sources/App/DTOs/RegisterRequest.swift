import Fluent
import Vapor

struct RegisterRequest: Content {
    let id: Int?
    let name: String
    let email: String
    let password: String
    let avatar: File?
}

extension RegisterRequest {
    func toModel() -> User {
        let model = User()
        model.id = id
        model.name = name
        model.email = email
        model.password = password
        return model
    }
}

extension RegisterRequest: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(3...))
        validations.add("password", as: String.self, is: .count(3...))
        validations.add("email", as: String.self, is: .email)
    }
}
