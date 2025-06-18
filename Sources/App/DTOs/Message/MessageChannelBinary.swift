//
//  MessageChannelBinary.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 07/06/2025.
//

import Foundation

struct MessageChannelIncomingBinary {
    enum BinaryType: UInt8 {
        case heartbeat = 0
        case message = 1
        case readMessages = 2
        case editMessage = 3
        case deleteMessage = 4
    }
    
    let type: BinaryType
    let payload: Data
    
    var binaryData: Data {
        var data = Data()
        data.append(type.rawValue)
        data.append(payload)
        return data
    }
    
    static func convert(from data: Data) -> Self? {
        guard !data.isEmpty, let type = BinaryType(rawValue: data[0]) else { return nil }
        
        let payload = data.dropFirst()
        return .init(type: type, payload: payload)
    }
}

struct MessageChannelOutgoingBinary {
    enum BinaryType: UInt8 {
        case heartbeat = 0
        case message = 1
        case readMessages = 2
        case error = 255
    }
    
    let type: BinaryType
    let payload: Data
    
    var binaryData: Data {
        var data = Data()
        data.append(type.rawValue)
        data.append(payload)
        return data
    }
    
    static func convert(from data: Data) -> Self? {
        guard !data.isEmpty, let type = BinaryType(rawValue: data[0]) else { return nil }
        
        let payload = data.dropFirst()
        return .init(type: type, payload: payload)
    }
}
