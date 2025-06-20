import Foundation
import Vapor

enum Constants {
    static let ACCESS_TOKEN_LIFETIME: Double = 60 * 15 // 15 mins
    static let REFRESH_TOKEN_LIFETIME: Double = 60 * 60 * 24 * 7 // 7 days
    
    static let AVATARS_DIRECTORY: String = "avatars/"
    
    static let WEB_SOCKET_SEND_DATA_RETRY_TIMES: UInt = 3
    static let WEB_SOCKET_CONNECTION_ALIVE_INTERVAL: TimeInterval = 90
    static let WEB_SOCKET_CONNECTION_ALIVE_CHECKING_INTERVAL: TimeInterval = 60
    
    static let REGISTER_PAYLOAD_MAX_SIZE: ByteCount = "1mb"
    
    static let EDITABLE_MESSAGE_INTERVAL: TimeInterval = 60 * 15
    
    static let MESSAGE_DELETED_TEXT = "Message deleted."
}

extension TimeInterval {
    static var accessTokenLifetime: TimeInterval {
        Constants.ACCESS_TOKEN_LIFETIME
    }
    
    static var refreshTokenLifetime: TimeInterval {
        Constants.REFRESH_TOKEN_LIFETIME
    }
}
