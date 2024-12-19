import Vapor

enum MessageError: AbortError, DebuggableError {
    case contactIDInvalid
    case contactNotFound
    case contactIsBlocked
    
    var status: HTTPResponseStatus {
        switch self {
        case .contactIDInvalid:
            .badRequest
        case .contactNotFound:
            .notFound
        case .contactIsBlocked:
            .forbidden
        }
    }
    
    var reason: String {
        switch self {
        case .contactIDInvalid:
            "Contact id invalid"
        case .contactNotFound:
            "Contact not found"
        case .contactIsBlocked:
            "Contact is blocked"
        }
    }
    
    var identifier: String {
        switch self {
        case .contactIDInvalid:
            "contact_id_invalid"
        case .contactNotFound:
            "contact_not_found"
        case .contactIsBlocked:
            "contact_is_blocked"
        }
    }
}
