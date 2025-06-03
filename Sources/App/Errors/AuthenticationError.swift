import Vapor

enum AuthenticationError: AbortError, DebuggableError {
    case userNotFound
    case accessTokenInvalid
    case refreshTokenInvalid
    case databaseError
    
    var status: HTTPResponseStatus {
        switch self {
        case .userNotFound:
            .notFound
        case .accessTokenInvalid:
            .unauthorized
        case .refreshTokenInvalid:
            .unauthorized
        case .databaseError:
            .internalServerError
        }
    }
    
    var reason: String {
        switch self {
        case .userNotFound:
            "User not found"
        case .accessTokenInvalid:
            "Access token invalid"
        case .refreshTokenInvalid:
            "Refresh token invalid"
        case .databaseError:
            "Database error"
        }
    }
    
    var identifier: String {
        switch self {
        case .userNotFound:
            "user_not_found"
        case .accessTokenInvalid:
            "access_token_invalid"
        case .refreshTokenInvalid:
            "refresh_token_invalid"
        case .databaseError:
            "database_error"
        }
    }
}
