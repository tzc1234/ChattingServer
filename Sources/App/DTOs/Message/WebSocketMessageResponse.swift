//
//  WebSocketMessageResponse.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 08/05/2025.
//

import Vapor

struct WebSocketMessageResponse: Content {
    struct Metadata: Content {
        let previousID: Int?
        
        enum CodingKeys: String, CodingKey {
            case previousID = "previous_id"
        }
    }
    
    let message: MessageResponse
    let metadata: Metadata
}
