//
//  WebSocketStore.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 08/06/2025.
//

import Vapor

actor WebSocketStore {
    private struct WebSocketConnection {
        let webSocket: WebSocket
        let timestamp: Date
        
        func newInstance(timestamp: Date) -> WebSocketConnection {
            WebSocketConnection(webSocket: webSocket, timestamp: timestamp)
        }
    }
    
    private var store = [ContactID: [UserID: WebSocketConnection]]()
    
    init() {
        Task { [weak self] in
            guard let self else { return }
            
            while true {
                if await !store.isEmpty {
                    let now = Date.now
                    for (_, connections) in await store {
                        for (userID, connection) in connections {
                            let aliveInterval = Constants.WEB_SOCKET_CONNECTION_ALIVE_INTERVAL
                            if now.timeIntervalSince(connection.timestamp) > aliveInterval {
                                try? await connection.webSocket.close(code: .goingAway)
                            }
                        }
                    }
                }
                
                try? await Task.sleep(for: .seconds(Constants.WEB_SOCKET_CONNECTION_ALIVE_CHECKING_INTERVAL))
            }
        }
    }
    
    func add(_ ws: WebSocket, for contactID: ContactID, userID: UserID) {
        store[contactID, default: [:]][userID] = WebSocketConnection(webSocket: ws, timestamp: .now)
    }
    
    func updateTimestampNow(for contactID: ContactID, userID: UserID) {
        guard let connection = store[contactID]?[userID] else { return }
        
        store[contactID]?[userID] = connection.newInstance(timestamp: .now)
    }
    
    func get(for contactID: ContactID) -> [WebSocket] {
        guard let contactWebSockets = store[contactID] else { return [] }
        
        return contactWebSockets.map(\.value.webSocket)
    }
    
    func get(for contactID: ContactID, userID: UserID) -> WebSocket? {
        guard let webSockets = store[contactID] else { return nil }
        
        return webSockets[userID]?.webSocket
    }
    
    func remove(for contactID: ContactID, userID: UserID) {
        store[contactID]?[userID] = nil
        
        if store[contactID]?.isEmpty == true {
            store[contactID] = nil
        }
    }
    
    func isExisted(for contactID: ContactID, userID: UserID) -> Bool {
        store[contactID]?[userID] != nil
    }
}
