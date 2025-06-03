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
    func sendMessageNotification(deviceToken: String, forUserID: Int, contact: ContactResponse, messageText: String) async
    func sendReadMessagesNotification(deviceToken: String, forUserID: Int, contactID: Int, untilMessageID: Int) async
}

actor DefaultAPNSHandler: APNSHandler {
    private struct Payload: Codable {
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
            payload: Payload(action: "new_contact_added", for_user_id: forUserID, contact: contact),
            mutableContent: 1
        )
        await sendAlert(alert, with: deviceToken)
    }
    
    func sendMessageNotification(deviceToken: String,
                                 forUserID: Int,
                                 contact: ContactResponse,
                                 messageText: String) async {
        let alert = APNSAlertNotification(
            alert: APNSAlertNotificationContent(
                title: .raw(contact.responder.name),
                body: .raw(messageText)
            ),
            expiration: .immediately,
            priority: .immediately,
            topic: configuration.bundleID,
            payload: Payload(action: "message", for_user_id: forUserID, contact: contact),
            threadID: "message-\(contact.id)",
            mutableContent: 1
        )
        await sendAlert(alert, with: deviceToken)
    }
    
    private func sendAlert<Payload>(_ alert: APNSAlertNotification<Payload>, with deviceToken: String) async {
        do {
            try await app.apns.client.sendAlertNotification(alert, deviceToken: deviceToken)
        } catch {
            app.logger.error(Logger.Message(stringLiteral: error.localizedDescription))
        }
    }
}

extension DefaultAPNSHandler {
    private struct ReadMessagesPayload: Codable {
        let action: String
        let for_user_id: Int
        let contact_id: Int
        let until_message_id: Int
        let timestamp: Date
    }
    
    func sendReadMessagesNotification(deviceToken: String, forUserID: Int, contactID: Int, untilMessageID: Int) async {
        let notification = APNSBackgroundNotification(
            expiration: .immediately,
            topic: configuration.bundleID,
            payload: ReadMessagesPayload(
                action: "read_messages",
                for_user_id: forUserID,
                contact_id: contactID,
                until_message_id: untilMessageID,
                timestamp: .now
            )
        )
        
        do {
            try await app.apns.client.sendBackgroundNotification(notification, deviceToken: deviceToken)
        } catch {
            app.logger.error(Logger.Message(stringLiteral: error.localizedDescription))
        }
    }
}
