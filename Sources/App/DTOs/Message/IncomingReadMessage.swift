//
//  IncomingReadMessage.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 07/06/2025.
//

import Vapor

struct IncomingReadMessage: Content {
    let untilMessageID: Int
    
    enum CodingKeys: String, CodingKey {
        case untilMessageID = "until_message_id"
    }
}
