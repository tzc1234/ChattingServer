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
        return try await getContactsResponse(for: currentUserID, on: req.db)
    }
    
    @Sendable
    private func create(req: Request) async throws -> ContactsResponse {
        let payload = try req.auth.require(Payload.self)
        let contactRequest = try req.content.decode(ContactRequest.self)
        let currentUserID = payload.userID
        try await newContact(for: currentUserID, with: contactRequest.responderEmail, on: req.db)
        return try await getContactsResponse(for: currentUserID, on: req.db)
    }
    
    private func newContact(for currentUserID: Int, with responderEmail: String, on db: Database) async throws {
        guard let responder = try await User.query(on: db)
            .filter(\.$email == responderEmail)
            .first(), let responderID = try? responder.requireID()
        else {
            throw Abort(.notFound, reason: "Responder not found", identifier: "responder_not_found")
        }
        
        guard currentUserID != responderID else {
            throw Abort(.conflict, reason: "Responder cannot be the same as current user", identifier: "responder_same_as_current_user")
        }
        
        try await saveNewContact(with: currentUserID, and: responderID, on: db)
    }
    
    private func saveNewContact(with currentUserID: Int, and responderID: Int, on db: Database) async throws {
        let contact = if currentUserID < responderID {
            Contact(userID1: currentUserID, userID2: responderID)
        } else {
            Contact(userID1: responderID, userID2: currentUserID)
        }
        try await contact.save(on: db)
    }
    
    private func getContactsResponse(for currentUserID: Int, on db: Database) async throws -> ContactsResponse {
        return try await Contact.query(on: db)
            .group(.or) { $0.filter(\.$user1.$id == currentUserID).filter(\.$user2.$id == currentUserID) }
            .with(\.$blockedBy)
            .all()
            .toResponse(currentUserID: currentUserID, db: db)
    }
}

private extension [Contact] {
    func toResponse(currentUserID: Int, db: Database) async throws -> ContactsResponse {
        var contactResponses = [ContactResponse]()
        for contact in self {
            let responder = try await loadResponder(from: contact, currentUserID: currentUserID, on: db)
            
            contactResponses.append(
                ContactResponse(
                    responder: responder.toResponse(),
                    blockedByUserEmail: contact.blockedBy?.email,
                    unreadMessageCount: try await contact.unreadMessagesCount(db: db)
                )
            )
        }
        return ContactsResponse(contacts: contactResponses)
    }
    
    private func loadResponder(from contact: Contact, currentUserID: Int, on db: Database) async throws -> User {
        if contact.$user1.id != currentUserID {
            try await contact.$user1.get(on: db)
        } else {
            try await contact.$user2.get(on: db)
        }
    }
}
