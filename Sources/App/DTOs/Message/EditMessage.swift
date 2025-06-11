//
//  EditMessage.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 10/06/2025.
//

import Vapor

struct EditMessage: Content {
    let messageID: Int
    let text: String
    
    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case text
    }
}
