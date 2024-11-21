import Vapor

enum ContactError: AbortError, DebuggableError {
    case responderNotFound
    case responderSameAsCurrentUser
    
    var status: HTTPResponseStatus {
        switch self {
        case .responderNotFound:
            .notFound
        case .responderSameAsCurrentUser:
            .conflict
        }
    }
    
    var reason: String {
        switch self {
        case .responderNotFound:
            "Responder not found"
        case .responderSameAsCurrentUser:
            "Responder cannot be the same as current user"
        }
    }
    
    var identifier: String {
        switch self {
        case .responderNotFound:
            "responder_not_found"
        case .responderSameAsCurrentUser:
            "responder_same_as_current_user"
        }
    }
}
