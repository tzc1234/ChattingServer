import Vapor

struct ContactController {
    private var defaultLimit: Int { 20 }
    
    private let contactRepository: ContactRepository
    private let userRepository: UserRepository
    private let avatarLinkLoader: AvatarLinkLoader
    
    init(contactRepository: ContactRepository,
         userRepository: UserRepository,
         avatarLinkLoader: AvatarLinkLoader) {
        self.contactRepository = contactRepository
        self.userRepository = userRepository
        self.avatarLinkLoader = avatarLinkLoader
    }
    
    @Sendable
    private func index(req: Request) async throws -> ContactsResponse {
        let indexRequest = try req.query.decode(ContactIndexRequest.self)
        let currentUserID = try req.auth.require(Payload.self).userID
        return try await contactsResponse(
            for: currentUserID,
            before: indexRequest.before,
            limit: indexRequest.limit
        )
    }
    
    private func contactsResponse(for currentUserID: Int,
                                  before: Date? = nil,
                                  limit: Int? = nil) async throws -> ContactsResponse {
        let contacts = try await contactRepository.getContacts(
            for: currentUserID,
            before: before,
            limit: limit ?? defaultLimit
        )
        return try await contacts.toResponse(
            currentUserID: currentUserID,
            contactRepository: contactRepository,
            avatarLink: avatarLink()
        )
    }
    
    @Sendable
    private func create(req: Request) async throws -> ContactResponse {
        let currentUserID = try req.auth.require(Payload.self).userID
        let responderEmail = try req.content.decode(ContactRequest.self).responderEmail
        let contact = try await contact(for: currentUserID, with: responderEmail)
        return try await contactResponse(with: contact, currentUserID: currentUserID)
    }
    
    private func contact(for currentUserID: Int, with responderEmail: String) async throws -> Contact {
        guard let responderID = try await userRepository.findBy(email: responderEmail)?.requireID() else {
            throw ContactError.responderNotFound
        }
        
        guard currentUserID != responderID else {
            throw ContactError.responderSameAsCurrentUser
        }
        
        return try await contactRepository.createBy(userID: currentUserID, anotherUserID: responderID)
    }
    
    @Sendable
    private func block(req: Request) async throws -> ContactResponse {
        let contactID = try ValidatedContactID(req.parameters).value
        let currentUserID = try req.auth.require(Payload.self).userID
        
        guard let contact = try await contactRepository.findBy(id: contactID, userID: currentUserID) else {
            throw ContactError.contactNotFound
        }
        
        guard contact.blockedBy == nil else {
            throw ContactError.contactAlreadyBlocked
        }
        
        try await contactRepository.update(contact, blockedByUserID: currentUserID)
        
        return try await contactResponse(with: contact, currentUserID: currentUserID)
    }
    
    @Sendable func unblock(req: Request) async throws -> ContactResponse {
        let contactID = try ValidatedContactID(req.parameters).value
        let currentUserID = try req.auth.require(Payload.self).userID
        
        guard let contact = try await contactRepository.findBy(id: contactID, userID: currentUserID) else {
            throw ContactError.contactNotFound
        }
        
        guard contact.blockedBy != nil else {
            throw ContactError.contactIsNotBlocked
        }
        
        guard contact.$blockedBy.id == currentUserID else {
            throw ContactError.contactIsNotBlockedByCurrentUser
        }
        
        try await contactRepository.update(contact, blockedByUserID: nil)
        
        return try await contactResponse(with: contact, currentUserID: currentUserID)
    }
    
    private func contactResponse(with contact: Contact, currentUserID: Int) async throws -> ContactResponse {
        try await contact.toResponse(
            currentUserID: currentUserID,
            contactRepository: contactRepository,
            avatarLink: avatarLink()
        )
    }
    
    private func avatarLink() -> (String?) async -> String? {
        { [weak avatarLinkLoader] filename in
            guard let filename else { return nil }
            
            return await avatarLinkLoader?.get(filename: filename)
        }
    }
}

extension ContactController: RouteCollection {
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
}

private extension [Contact] {
    func toResponse(currentUserID: Int,
                    contactRepository: ContactRepository,
                    avatarLink: (String?) async -> String?) async throws -> ContactsResponse {
        var contactResponses = [ContactResponse]()
        for contact in self {
            contactResponses.append(try await contact.toResponse(
                currentUserID: currentUserID,
                contactRepository: contactRepository,
                avatarLink: avatarLink
            ))
        }
        return ContactsResponse(contacts: contactResponses)
    }
}

private extension Contact {
    func toResponse(currentUserID: Int,
                    contactRepository: ContactRepository,
                    avatarLink: (String?) async -> String?) async throws -> ContactResponse {
        guard let lastUpdate = try await contactRepository.lastUpdateFor(self) else { throw ContactError.databaseError }
        
        return try await ContactResponse(
            id: requireID(),
            responder: contactRepository.responderFor(self, by: currentUserID).toResponse(avatarLink: avatarLink),
            blockedByUserID: $blockedBy.id,
            unreadMessageCount: contactRepository.unreadMessagesCountFor(self, senderIsNot: currentUserID),
            lastUpdate: lastUpdate,
            lastMessage: contactRepository.lastMessageFor(self, senderIsNot: currentUserID)?.toResponse()
        )
    }
}
