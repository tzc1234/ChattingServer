//
//  APNSHandler.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 01/04/2025.
//

import APNS
@preconcurrency import APNSCore
import Vapor
import VaporAPNS

struct APNSConfiguration {
    let p8KeyPath: String
    let keyID: String
    let teamID: String
    let bundleID: String
    let environment: String
}

actor APNSHandler {
    private struct Payload: Codable {
        let action: String
        let user_id: Int
    }
    
    private let app: Application
    private let configuration: APNSConfiguration
    
    init(app: Application, configuration: APNSConfiguration) throws {
        self.app = app
        self.configuration = configuration
        
        Task {
            let apnsConfig = await APNSClientConfiguration(
                authenticationMethod: .jwt(
                    privateKey: try .loadFrom(string: loadP8Key()),
                    keyIdentifier: configuration.keyID,
                    teamIdentifier: configuration.teamID
                ),
                environment: configuration.environment == "development" ? .development : .production
            )
            
            app.apns.containers.use(
                apnsConfig,
                eventLoopGroupProvider: .shared(app.eventLoopGroup),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder(),
                as: .default
            )
        }
    }
    
    private func loadP8Key() throws -> String {
        let keyPath = app.directory.workingDirectory + configuration.p8KeyPath
        return try String(contentsOfFile: keyPath)
    }
    
    func sendNewContactAddedBackgroundNotification(deviceToken: String, userID: Int) async {
        let backgroundNotification = APNSBackgroundNotification(
            expiration: .immediately,
            topic: configuration.bundleID,
            payload: Payload(action: "new_contact_added", user_id: userID)
        )
        
        do {
            try await app.apns.client.sendBackgroundNotification(backgroundNotification, deviceToken: deviceToken)
        } catch {
            print("APNS error: \(error)")
        }
    }
}
