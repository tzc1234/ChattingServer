import Vapor

enum MessageError: AbortError, DebuggableError {
    case contactIDInvalid
    case contactNotFound
    case contactIsBlocked
    case databaseError
    
    var status: HTTPResponseStatus {
        switch self {
        case .contactIDInvalid:
            .badRequest
        case .contactNotFound:
            .notFound
        case .contactIsBlocked:
            .forbidden
        case .databaseError:
            .internalServerError
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
        case .databaseError:
            "Database error"
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
        case .databaseError:
            "database_error"
        }
    }
}
