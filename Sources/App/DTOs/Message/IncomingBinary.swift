//
//  IncomingBinary.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 07/06/2025.
//

import Foundation

enum IncomingBinaryType: UInt8 {
    // reserve 0
    case message = 1
    case readMessages = 2
}

struct IncomingBinary {
    let type: IncomingBinaryType
    let payload: Data
    
    var binaryData: Data {
        var data = Data()
        data.append(type.rawValue)
        data.append(payload)
        return data
    }
    
    static func convert(from data: Data) -> IncomingBinary? {
        guard !data.isEmpty, let type = IncomingBinaryType(rawValue: data[0]) else { return nil }
        
        let payload = data.dropFirst()
        return IncomingBinary(type: type, payload: payload)
    }
}
