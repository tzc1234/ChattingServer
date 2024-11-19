import Vapor

struct MessageResponse: Content {
    let text: String
    let sender: UserResponse
    let isRead: Bool
}

struct MessagesResponse: Content {
    let messages: [MessageResponse]
}
