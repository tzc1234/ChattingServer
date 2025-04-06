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
    let keyP8FilePath: String
    let keyID: String
    let teamID: String
    let bundleID: String
    let environment: String
}

protocol APNSHandler: Sendable {
    func sendNewContactAddedNotification(deviceToken: String, forUserID: Int, contact: ContactResponse) async
}

actor DefaultAPNSHandler: APNSHandler {
    private struct NewContactAddedPayload: Codable {
        let action: String
        let for_user_id: Int
        let contact: ContactResponse
    }
    
    private let app: Application
    private let configuration: APNSConfiguration
    
    init(app: Application, configuration: APNSConfiguration) throws {
        self.app = app
        self.configuration = configuration
        
        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .loadFrom(string: String(contentsOfFile: configuration.keyP8FilePath)),
                keyIdentifier: configuration.keyID,
                teamIdentifier: configuration.teamID
            ),
            environment: configuration.environment == "development" ? .development : .production
        )
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        app.apns.containers.use(
            apnsConfig,
            eventLoopGroupProvider: .shared(app.eventLoopGroup),
            responseDecoder: decoder,
            requestEncoder: encoder,
            as: .default
        )
    }
    
    func sendNewContactAddedNotification(deviceToken: String, forUserID: Int, contact: ContactResponse) async {
        let alert = APNSAlertNotification(
            alert: APNSAlertNotificationContent(
                title: .raw("New contact received"),
                body: .raw("\(contact.responder.name) added you as a new contact.")
            ),
            expiration: .immediately,
            priority: .immediately,
            topic: configuration.bundleID,
            payload: NewContactAddedPayload(action: "new_contact_added", for_user_id: forUserID, contact: contact),
            mutableContent: 1
        )
        
        do {
            try await app.apns.client.sendAlertNotification(alert, deviceToken: deviceToken)
        } catch {
            app.logger.error(Logger.Message(stringLiteral: error.localizedDescription))
        }
    }
}
