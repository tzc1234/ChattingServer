import Vapor

actor WebSocketStore {
    private var store = [ContactID: [UserID: WebSocket]]()
    
    func add(_ ws: WebSocket, for contactID: ContactID, userID: UserID) {
        store[contactID, default: [:]][userID] = ws
    }
    
    func get(for contactID: ContactID) -> [WebSocket] {
        guard let contactWebSockets = store[contactID] else { return [] }
        
        return contactWebSockets.map(\.value)
    }
    
    func get(for contactID: ContactID, userID: UserID) -> WebSocket? {
        guard let webSockets = store[contactID] else { return nil }
        
        return webSockets[userID]
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
