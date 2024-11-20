import Vapor

actor WebSocketStore {
    private var store = [ContactID: [UserID: WebSocket]]()
    
    func add(_ ws: WebSocket, for contactID: ContactID, with userID: UserID) async {
        store[contactID, default: [:]][userID] = ws
    }
    
    func get(for contactID: ContactID) async -> [WebSocket] {
        guard let contactWebSockets = store[contactID] else { return [] }
        
        return contactWebSockets.map(\.value)
    }
    
    func remove(for contactID: ContactID, with userID: UserID) async {
        store[contactID]?[userID] = nil
    }
}
