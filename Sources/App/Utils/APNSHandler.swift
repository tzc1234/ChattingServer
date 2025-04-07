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
    func sendMessageNotification(deviceToken: String, message: Message, receiverID: Int) async throws
}

actor DefaultAPNSHandler: APNSHandler {
    private struct NewContactAddedPayload: Codable {
        let action: String
        let for_user_id: Int
        let contact: ContactResponse
    }
    
    private struct MessagePayload: Codable {
        let action: String
        let for_user_id: Int
        let sender_id: Int
        let sender_name: String
        let avatar_url: String?
    }
    
    private let app: Application
    private let avatarLinkLoader: AvatarLinkLoader
    private let configuration: APNSConfiguration
    
    init(app: Application, avatarLinkLoader: AvatarLinkLoader, configuration: APNSConfiguration) throws {
        self.app = app
        self.avatarLinkLoader = avatarLinkLoader
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
        await send(alert, with: deviceToken)
    }
    
    func sendMessageNotification(deviceToken: String, message: Message, receiverID: Int) async throws {
        let avatarURL: String? = await {
            guard let filename = message.sender.avatarFilename else { return nil }
            return await avatarLinkLoader.get(filename: filename)
        }()
        let alert = APNSAlertNotification(
            alert: APNSAlertNotificationContent(
                title: .raw(message.sender.name),
                body: .raw(message.text)
            ),
            expiration: .immediately,
            priority: .immediately,
            topic: configuration.bundleID,
            payload: MessagePayload(
                action: "message",
                for_user_id: receiverID,
                sender_id: try message.sender.requireID(),
                sender_name: message.sender.name,
                avatar_url: avatarURL
            ),
            threadID: "message-\(try message.sender.requireID())",
            mutableContent: 1
        )
        await send(alert, with: deviceToken)
    }
    
    private func send<Payload>(_ alert: APNSAlertNotification<Payload>, with deviceToken: String) async {
        do {
            try await app.apns.client.sendAlertNotification(alert, deviceToken: deviceToken)
        } catch {
            app.logger.error(Logger.Message(stringLiteral: error.localizedDescription))
        }
    }
}
