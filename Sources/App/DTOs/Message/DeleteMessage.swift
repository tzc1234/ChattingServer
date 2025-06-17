//
//  DeleteMessage.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 17/06/2025.
//

import Vapor

struct DeleteMessage: Content {
    let messageID: Int
    
    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
    }
}
