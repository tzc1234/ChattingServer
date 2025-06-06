//
//  UpdateUserRequest.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 04/06/2025.
//

import Vapor

struct UpdateUserRequest: Content {
    let name: String
    let avatar: File?
}

extension UpdateUserRequest: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(3...))
    }
}
