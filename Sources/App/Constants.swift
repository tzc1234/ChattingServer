import Foundation

enum Constants {
    static let ACCESS_TOKEN_LIFETIME: Double = 60 * 15 // 15 mins
    static let REFRESH_TOKEN_LIFETIME: Double = 60 * 60 * 24 * 7 // 7 days
}

extension TimeInterval {
    static var accessTokenLifetime: TimeInterval {
        Constants.ACCESS_TOKEN_LIFETIME
    }
    
    static var refreshTokenLifetime: TimeInterval {
        Constants.REFRESH_TOKEN_LIFETIME
    }
}
