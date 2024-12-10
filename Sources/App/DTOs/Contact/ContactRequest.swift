import Vapor

struct ContactRequest: Content {
    let responderEmail: String
    
    enum CodingKeys: String, CodingKey {
        case responderEmail = "responder_email"
    }
}
