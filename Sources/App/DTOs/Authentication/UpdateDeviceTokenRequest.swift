//
//  UpdateDeviceTokenRequest.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 02/04/2025.
//

import Vapor

struct UpdateDeviceTokenRequest: Content {
    let deviceToken: String
    
    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
    }
}

extension UpdateDeviceTokenRequest: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("device_token", as: String.self, is: !.empty, customFailureDescription: "Device token is empty!")
    }
}
