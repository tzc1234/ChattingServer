import Vapor

enum MessageError: AbortError, DebuggableError {
    case contactNotFound
    case contactIsBlocked
    case databaseError
    case messageNotFound
    case messageUnableEdit
    
    var status: HTTPResponseStatus {
        switch self {
        case .contactNotFound:
            .notFound
        case .contactIsBlocked:
            .forbidden
        case .databaseError:
            .internalServerError
        case .messageNotFound:
            .notFound
        case .messageUnableEdit:
            .forbidden
        }
    }
    
    var reason: String {
        switch self {
        case .contactNotFound:
            "Contact not found"
        case .contactIsBlocked:
            "Contact is blocked"
        case .databaseError:
            "Database error"
        case .messageNotFound:
            "Message not found"
        case .messageUnableEdit:
            "Cannot edit a message from \(Int(Constants.EDITABLE_MESSAGE_INTERVAL/60)) minutes ago"
        }
    }
    
    var identifier: String {
        switch self {
        case .contactNotFound:
            "contact_not_found"
        case .contactIsBlocked:
            "contact_is_blocked"
        case .databaseError:
            "database_error"
        case .messageNotFound:
            "message_not_found"
        case .messageUnableEdit:
            "message_unable_edit"
        }
    }
}
