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
    
    func remove(for contactID: ContactID, userID: UserID) {
        store[contactID]?[userID] = nil
    }
    
    func isExisted(for contactID: ContactID, userID: UserID) -> Bool {
        store[contactID]?[userID] != nil
    }
}
