import Foundation

enum Constants {
    static let ACCESS_TOKEN_LIFETIME: Double = 60 * 1500 // TODO: Set this to 15 mins.
    static let REFRESH_TOKEN_LIFETIME: Double = 60 * 60 * 24 * 7 // 7 days
    
    static let AVATARS_DIRECTORY: String = "avatars/"
    static let WEB_SOCKET_SEND_DATA_RETRY_TIMES: UInt = 3
}

extension TimeInterval {
    static var accessTokenLifetime: TimeInterval {
        Constants.ACCESS_TOKEN_LIFETIME
    }
    
    static var refreshTokenLifetime: TimeInterval {
        Constants.REFRESH_TOKEN_LIFETIME
    }
}
