//
//  MessageEditHistory.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 10/06/2025.
//

import Fluent
import Vapor

final class MessageEditHistory: Model, @unchecked Sendable {
    static let schema = "message_edit_histories"
    
    @ID(custom: "id", generatedBy: .database)
    var id: Int?
    
    @Parent(key: "message_id")
    var message: Message
    
    @Field(key: "previous_text")
    var previousText: String
    
    @Field(key: "new_text")
    var newText: String
    
    @Timestamp(key: "edited_at", on: .create)
    var editedAt: Date?
    
    init() { }
    
    init(id: Int? = nil, messageID: Message.IDValue, previousText: String, newText: String) {
        self.id = id
        self.$message.id = messageID
        self.previousText = previousText
        self.newText = newText
    }
}
