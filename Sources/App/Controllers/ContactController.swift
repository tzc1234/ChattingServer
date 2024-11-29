import Fluent
import Vapor

struct ContactController: RouteCollection {
    private var defaultLimit: Int { 20 }
    private let avatarDirectoryPath: @Sendable () -> (String)
    
    init(avatarDirectoryPath: @escaping @Sendable () -> String) {
        self.avatarDirectoryPath = avatarDirectoryPath
    }
    
    func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped("contacts")
            .grouped(AccessTokenGuardMiddleware(), UserAuthenticator())
        
        protected.get(use: index)
        protected.post(use: create)
        
        protected.group(":contact_id") { routes in
            routes.patch("block", use: block)
            routes.patch("unblock", use: unblock)
        }
    }
    
    @Sendable
    private func index(req: Request) async throws -> ContactsResponse {
        let indexRequest = try req.content.decode(ContactIndexRequest.self)
        let currentUserID = try req.auth.require(Payload.self).userID
        return try await getContactsResponse(
            for: currentUserID,
            beforeContactID: indexRequest.beforeContactID,
            afterContactID: indexRequest.afterContactID,
            limit: indexRequest.limit,
            req: req
        )
    }
    
    @Sendable
    private func create(req: Request) async throws -> ContactsResponse {
        let currentUserID = try req.auth.require(Payload.self).userID
        let contactRequest = try req.content.decode(ContactRequest.self)
        try await newContact(for: currentUserID, with: contactRequest.responderEmail, on: req.db)
        return try await getContactsResponse(for: currentUserID, req: req)
    }
    
    private func newContact(for currentUserID: Int, with responderEmail: String, on db: Database) async throws {
        guard let responder = try await User.query(on: db)
            .filter(\.$email == responderEmail)
            .first(), let responderID = try? responder.requireID()
        else {
            throw ContactError.responderNotFound
        }
        
        guard currentUserID != responderID else {
            throw ContactError.responderSameAsCurrentUser
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
    
    private func getContactsResponse(for currentUserID: Int,
                                     beforeContactID: Int? = nil,
                                     afterContactID: Int? = nil,
                                     limit: Int? = nil,
                                     req: Request) async throws -> ContactsResponse {
        var query = Contact.query(on: req.db)
            .filter(by: currentUserID)
            .with(\.$blockedBy)
            .sort(\.$id, .descending)
            .limit(limit ?? defaultLimit)
        
        if let beforeContactID {
            query = query.filter(\.$id < beforeContactID)
        } else if let afterContactID {
            query = query.filter(\.$id > afterContactID)
        }
        
        return try await query.all()
            .toResponse(
                currentUserID: currentUserID,
                req: req,
                avatarDirectoryPath: avatarDirectoryPath()
            )
    }
    
    @Sendable
    private func block(req: Request) async throws -> ContactResponse {
        let contactID = try extractContactID(from: req.parameters)
        let currentUserID = try req.auth.require(Payload.self).userID
        
        guard let contact = try await getContact(for: currentUserID, contactID: contactID, req: req) else {
            throw ContactError.contactNotFound
        }
        
        guard contact.blockedBy == nil else {
            throw ContactError.contactAlreadyBlocked
        }
        
        contact.$blockedBy.id = currentUserID
        try await contact.update(on: req.db)
        
        return try await contact.toResponse(
            currentUserID: currentUserID,
            req: req,
            avatarDirectoryPath: avatarDirectoryPath()
        )
    }
    
    @Sendable func unblock(req: Request) async throws -> ContactResponse {
        let contactID = try extractContactID(from: req.parameters)
        let currentUserID = try req.auth.require(Payload.self).userID
        
        guard let contact = try await getContact(for: currentUserID, contactID: contactID, req: req) else {
            throw ContactError.contactNotFound
        }
        
        guard contact.blockedBy != nil else {
            throw ContactError.contactIsNotBlocked
        }
        
        guard contact.$blockedBy.id == currentUserID else {
            throw ContactError.contactIsNotBlockedByCurrentUser
        }
        
        contact.$blockedBy.id = nil
        try await contact.update(on: req.db)
        
        return try await contact.toResponse(
            currentUserID: currentUserID,
            req: req,
            avatarDirectoryPath: avatarDirectoryPath()
        )
    }
    
    private func extractContactID(from parameters: Parameters) throws -> Int {
        guard let contactIDString = parameters.get("contact_id"), let contactID = Int(contactIDString) else {
            throw ContactError.contactIDInvalid
        }
        
        return contactID
    }
    
    private func getContact(for currentUserID: Int, contactID: Int, req: Request) async throws -> Contact? {
        try await Contact.query(on: req.db)
            .filter(by: currentUserID)
            .filter(\.$id == contactID)
            .with(\.$blockedBy)
            .first()
    }
}

private extension Contact {
    func toResponse(currentUserID: Int, req: Request, avatarDirectoryPath: String) async throws -> ContactResponse {
        try ContactResponse(
            id: requireID(),
            responder: await loadResponder(currentUserID: currentUserID, on: req.db)
                .toResponse(
                    app: req.application,
                    avatarDirectoryPath: avatarDirectoryPath
                ),
            blockedByUserID: $blockedBy.id,
            unreadMessageCount: await unreadMessagesCount(db: req.db)
        )
    }
    
    private func loadResponder(currentUserID: Int, on db: Database) async throws -> User {
        if $user1.id != currentUserID {
            try await $user1.get(on: db)
        } else {
            try await $user2.get(on: db)
        }
    }
}

private extension [Contact] {
    func toResponse(currentUserID: Int, req: Request, avatarDirectoryPath: String) async throws -> ContactsResponse {
        var contactResponses = [ContactResponse]()
        for contact in self {
            contactResponses.append(try await contact.toResponse(
                currentUserID: currentUserID,
                req: req,
                avatarDirectoryPath: avatarDirectoryPath
            ))
        }
        return ContactsResponse(contacts: contactResponses)
    }
}
