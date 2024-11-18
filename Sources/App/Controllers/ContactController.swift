import Fluent
import Vapor

struct ContactController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped("contacts")
            .grouped(AccessTokenGuardMiddleware(), UserAuthenticator())
        
        protected.get(use: index)
        protected.post(use: create)
    }
    
    @Sendable
    private func index(req: Request) async throws -> ContactsResponse {
        let payload = try req.auth.require(Payload.self)
        let currentUserID = payload.userID
        let db = req.db
        
        return try await getAllContacts(for: currentUserID, on: db)
            .toResponse(currentUserID: currentUserID, db: db)
    }
    
    @Sendable
    private func create(req: Request) async throws -> ContactsResponse {
        let payload = try req.auth.require(Payload.self)
        let contactRequest = try req.content.decode(ContactRequest.self)
        return try await makeContactsResponse(
            currentUserID: payload.userID,
            responderEmail: contactRequest.responderEmail,
            db: req.db
        )
    }
    
    private func makeContactsResponse(currentUserID: Int, responderEmail: String, db: Database) async throws -> ContactsResponse {
        guard let responder = try await User.query(on: db)
            .filter(\.$email == responderEmail)
            .first(), let responderID = try? responder.requireID()
        else {
            throw Abort(.notFound, reason: "Responder not found", identifier: "responder_not_found")
        }
        
        guard currentUserID != responderID else {
            throw Abort(.conflict, reason: "Responder cannot be the same as current user", identifier: "responder_same_as_current_user")
        }
        
        let contact = if currentUserID < responderID {
            Contact(userID1: currentUserID, userID2: responderID)
        } else {
            Contact(userID1: responderID, userID2: currentUserID)
        }
        try await contact.save(on: db)
        
        return try await getAllContacts(for: currentUserID, on: db).toResponse(currentUserID: currentUserID, db: db)
    }
    
    private func getAllContacts(for currentUserID: Int, on db: Database) async throws -> [Contact] {
        return try await Contact.query(on: db)
            .group(.or) { $0.filter(\.$user1.$id == currentUserID).filter(\.$user2.$id == currentUserID) }
            .with(\.$blockedBy)
            .all()
    }
}

private extension [Contact] {
    func toResponse(currentUserID: Int, db: Database) async throws -> ContactsResponse {
        var contactResponses = [ContactResponse]()
        for contact in self {
            let responder = if contact.$user1.id != currentUserID {
                try await contact.$user1.get(on: db)
            } else {
                try await contact.$user2.get(on: db)
            }
            
            contactResponses.append(
                ContactResponse(
                    responder: responder.toResponse(),
                    blockedByUserEmail: contact.blockedBy?.email
                )
            )
        }
        return ContactsResponse(contacts: contactResponses)
    }
}
