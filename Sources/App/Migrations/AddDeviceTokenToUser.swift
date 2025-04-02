//
//  AddDeviceTokenToUser.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 02/04/2025.
//

import Fluent

struct AddDeviceTokenToUser: AsyncMigration {
    func prepare(on database: any FluentKit.Database) async throws {
        try await database.schema(User.schema)
            .field("device_token", .string)
            .update()
    }
    
    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(User.schema)
                .deleteField("device_token")
                .update()
    }
}
