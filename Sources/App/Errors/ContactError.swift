import Vapor

enum ContactError: AbortError, DebuggableError {
    case responderNotFound
    case responderSameAsCurrentUser
    case contactIDInvalid
    case contactNotFound
    case contactAlreadyBlocked
    
    var status: HTTPResponseStatus {
        switch self {
        case .responderNotFound:
            .notFound
        case .responderSameAsCurrentUser:
            .conflict
        case .contactIDInvalid:
            .badRequest
        case .contactNotFound:
            .notFound
        case .contactAlreadyBlocked:
            .badRequest
        }
    }
    
    var reason: String {
        switch self {
        case .responderNotFound:
            "Responder not found"
        case .responderSameAsCurrentUser:
            "Responder cannot be the same as current user"
        case .contactIDInvalid:
            "Contact id invalid"
        case .contactNotFound:
            "Contact not found"
        case .contactAlreadyBlocked:
            "Contact is already blocked"
        }
    }
    
    var identifier: String {
        switch self {
        case .responderNotFound:
            "responder_not_found"
        case .responderSameAsCurrentUser:
            "responder_same_as_current_user"
        case .contactIDInvalid:
            "contact_id_invalid"
        case .contactNotFound:
            "contact_not_found"
        case .contactAlreadyBlocked:
            "contact_already_blocked"
        }
    }
}
