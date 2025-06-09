//
//  MessageChannelBinary.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 07/06/2025.
//

import Foundation

enum MessageChannelBinaryType: UInt8 {
    case heartbeat = 0
    case message = 1
    case readMessages = 2
}

struct MessageChannelBinary {
    let type: MessageChannelBinaryType
    let payload: Data
    
    var binaryData: Data {
        var data = Data()
        data.append(type.rawValue)
        data.append(payload)
        return data
    }
    
    static func convert(from data: Data) -> MessageChannelBinary? {
        guard !data.isEmpty, let type = MessageChannelBinaryType(rawValue: data[0]) else { return nil }
        
        let payload = data.dropFirst()
        return MessageChannelBinary(type: type, payload: payload)
    }
}
