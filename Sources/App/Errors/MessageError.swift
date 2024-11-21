import Vapor

enum MessageError: AbortError, DebuggableError {
    case databaseError
    case contactIDInvalid
    case contactNotFound
    case messagesNotFound
    
    var status: HTTPResponseStatus {
        switch self {
        case .databaseError:
            .internalServerError
        case .contactIDInvalid:
            .badRequest
        case .contactNotFound:
            .notFound
        case .messagesNotFound:
            .notFound
        }
    }
    
    var reason: String {
        switch self {
        case .databaseError:
            "Database error"
        case .contactIDInvalid:
            "Contact id invalid"
        case .contactNotFound:
            "Contact not found"
        case .messagesNotFound:
            "Messages not found"
        }
    }
    
    var identifier: String {
        switch self {
        case .databaseError:
            "database_error"
        case .contactIDInvalid:
            "contact_id_invalid"
        case .contactNotFound:
            "contact_not_found"
        case .messagesNotFound:
            "messages_not_found"
        }
    }
}
