import Vapor

enum ContactError: AbortError, DebuggableError {
    case responderNotFound
    case responderSameAsCurrentUser
    case contactIDInvalid
    case contactNotFound
    case contactAlreadyBlocked
    case contactIsNotBlocked
    case contactIsNotBlockedByCurrentUser
    case databaseError
    
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
        case .contactIsNotBlocked:
            .badRequest
        case .contactIsNotBlockedByCurrentUser:
            .badRequest
        case .databaseError:
            .internalServerError
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
        case .contactIsNotBlocked:
            "Contact is not blocked"
        case .contactIsNotBlockedByCurrentUser:
            "Contact is not blocked by current user, cannot be unblocked"
        case .databaseError:
            "Database error"
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
        case .contactIsNotBlocked:
            "contact_not_blocked"
        case .contactIsNotBlockedByCurrentUser:
            "contact_not_blocked_by_current_user"
        case .databaseError:
            "database_error"
        }
    }
}
