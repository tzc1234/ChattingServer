@testable import App
import XCTVapor
import Testing
import Fluent
import Vapor

@Suite("Contact routes tests")
struct ContactTests: AppTests, AvatarFileHelpers {
    @Test("new contact failure without a token")
    func newContactFailureWithoutToken() async throws {
        try await makeApp { app in
            try await app.test(.POST, .apiPath("contacts")) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("new contact failure with an invalid token")
    func newContactFailureWithInvalidToken() async throws {
        let invalidToken = "invalid-token"
        
        try await makeApp { app in
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: invalidToken)
            } afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("new contact failure with a non-exist responder email")
    func newContactFailureWithNonExistResponderEmail() async throws {
        try await makeApp { app in
            let nonExistResponderEmail = "non-exist@email.com"
            let contactRequest = ContactRequest(responderEmail: nonExistResponderEmail)
            let accessToken = try await createTokenResponse(app).accessToken
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .notFound)
            }
        }
    }
    
    @Test("new contact failure with responder is as same as current user")
    func mewContactFailureWithResponderSameAsCurrentUser() async throws {
        try await makeApp { app in
            let token = try await createTokenResponse(app)
            let currentUserEmail = token.user.email
            let contactRequest = ContactRequest(responderEmail: currentUserEmail)
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.accessToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                #expect(try errorReason(from: res) == "Responder cannot be the same as current user")
            }
        }
    }
    
    @Test("new contact success with currentUserID < responderID")
    func mewContactSuccessWithCurrentUserIDSmallerThanResponderID() async throws {
        try await makeApp { app in
            let (currentUser, currentUserToken) = try await createUserAndAccessToken(app)
            let (responder, _) = try await createUserAndAccessToken(app, email: "responder@email.com")
            let contactRequest = ContactRequest(responderEmail: responder.email)
            
            let currentUserID = try #require(currentUser.id)
            let responderID = try #require(responder.id)
            try #require(currentUserID < responderID)
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contact = try res.content.decode(ContactResponse.self)
                expect(
                    contact: contact,
                    as: try await responder.toResponse(app: app, directoryPath: testAvatarDirectoryPath)
                )
            }
        }
    }
    
    @Test("new contact success with currentUserID > responderID")
    func mewContactSuccessWithCurrentUserIDBiggerThanResponderID() async throws {
        try await makeApp { app in
            let (responder, _) = try await createUserAndAccessToken(app, email: "responder@email.com")
            let (currentUser, currentUserToken) = try await createUserAndAccessToken(app)
            let contactRequest = ContactRequest(responderEmail: responder.email)
            
            let currentUserID = try #require(currentUser.id)
            let responderID = try #require(responder.id)
            try #require(currentUserID > responderID)
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contact = try res.content.decode(ContactResponse.self)
                expect(
                    contact: contact,
                    as: try await responder.toResponse(app: app, directoryPath: testAvatarDirectoryPath)
                )
            }
        }
    }
    
    @Test("get contacts failure without a token")
    func getContactsFailureWithoutToken() async throws {
        try await makeApp { app in
            try await app.test(.GET, .apiPath("contacts")) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("get contacts failure with an invalid token")
    func getContactsFailureWithInvalidToken() async throws {
        let invalidToken = "invalid-token"
        
        try await makeApp { app in
            try await app.test(.GET, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: invalidToken)
            } afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("get empty contacts")
    func getEmptyContacts() async throws {
        try await makeApp { app in
            let tokenResponse = try await createTokenResponse(app)
            
            try await app.test(.GET, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: tokenResponse.accessToken)
                try req.query.encode(ContactIndexRequest(before: nil, limit: nil))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                let contactsResponse = try res.content.decode(ContactsResponse.self)
                #expect(contactsResponse.contacts.isEmpty)
            }
        }
    }
    
    @Test("get one contact")
    func getOneContact() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let expectedContactResponse = try await createContactResponse(
                user: currentUser,
                anotherUser: anotherUser,
                app: app
            )
            
            try await app.test(.GET, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.query.encode(ContactIndexRequest(before: nil, limit: nil))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contactsResponse = try res.content.decode(ContactsResponse.self)
                expect(contacts: contactsResponse.contacts, as: [expectedContactResponse])
            }
        }
    }
    
    @Test("get contacts with before date and limit")
    func getContactsWithBeforeDateAndLimit() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser1 = try await createUser(app, email: "another-user1@email.com")
            let anotherUser2 = try await createUser(app, email: "another-user2@email.com")
            let anotherUser3 = try await createUser(app, email: "another-user3@email.com")
            let anotherUser4 = try await createUser(app, email: "another-user4@email.com")
            
            let beforeDate = Date.now
            let smallerThanBeforeDateContact1 = makeContactDetailForTest(
                id: 100,
                user: currentUser,
                anotherUser: anotherUser1,
                senderID: try currentUser.requireID(),
                text: "text 100",
                lastUpdate: beforeDate.reducing(seconds: 1)
            )
            let equalToBeforeDateContact = makeContactDetailForTest(
                id: 200,
                user: currentUser,
                anotherUser: anotherUser2,
                senderID: try anotherUser2.requireID(),
                text: "text 200",
                lastUpdate: beforeDate
            )
            let greaterThanBeforeDateContact = makeContactDetailForTest(
                id: 300,
                user: currentUser,
                anotherUser: anotherUser3,
                senderID: try anotherUser3.requireID(),
                text: "text 300",
                lastUpdate: beforeDate.adding(seconds: 1)
            )
            let smallerThanBeforeDateContact2 = makeContactDetailForTest(
                id: 400,
                user: currentUser,
                anotherUser: anotherUser4,
                senderID: try anotherUser4.requireID(),
                text: "text 400",
                lastUpdate: beforeDate.reducing(seconds: 1)
            )
            let nonCurrentUserContact = makeContactDetailForTest(
                id: 500,
                user: anotherUser1,
                anotherUser: anotherUser2,
                senderID: try anotherUser1.requireID(),
                text: "text 500",
                lastUpdate: beforeDate.reducing(seconds: 1)
            )
            
            let expectedContactResponses = try await createContactResponses(
                contactDetails: [
                    smallerThanBeforeDateContact1,
                    equalToBeforeDateContact,
                    greaterThanBeforeDateContact,
                    smallerThanBeforeDateContact2,
                    nonCurrentUserContact
                ],
                app: app
            )
            .filter { [smallerThanBeforeDateContact1.id, smallerThanBeforeDateContact2.id].contains($0.id) }
            .sorted(by: { $0.lastUpdate > $1.lastUpdate })
            
            // test beforeDate
            try await app.test(.GET, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.query.encode(ContactIndexRequest(before: beforeDate, limit: nil))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contactsResponse = try res.content.decode(ContactsResponse.self)
                expect(contacts: contactsResponse.contacts, as: expectedContactResponses)
            }
            
            // test beforeDate with limit
            let limit = 1
            try await app.test(.GET, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.query.encode(ContactIndexRequest(before: beforeDate, limit: limit))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contactsResponse = try res.content.decode(ContactsResponse.self)
                expect(contacts: contactsResponse.contacts, as: Array(expectedContactResponses[..<limit]))
            }
        }
    }
    
    @Test("block contact failure without a token")
    func blockContactFailureWithoutToken() async throws {
        try await makeApp { app in
            try await app.test(.PATCH, .apiPath("contacts", "1", "block")) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("block contact failure with an invalid token")
    func blockContactFailureWithInvalidToken() async throws {
        let invalidToken = "invalid-token"
        
        try await makeApp { app in
            try await app.test(.PATCH, .apiPath("contacts", "1", "block")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: invalidToken)
            } afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("block contact failure with a non-exist contactID")
    func blockContactFailureWithNonExistContactID() async throws {
        try await makeApp { app in
            let tokenResponse = try await createTokenResponse(app)
            
            try await app.test(.PATCH, .apiPath("contacts", "1", "block")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: tokenResponse.accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .notFound)
                #expect(try errorReason(from: res) == "Contact not found")
            }
        }
    }
    
    @Test("block contact failure because is already blocked")
    func blockContactFailureBecauseAlreadyBlocked() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let alreadyBlockedContact = try await createContact(
                user: currentUser,
                anotherUser: anotherUser,
                blockedByUserID: anotherUser.requireID(),
                db: app.db
            )
            
            try await app.test(.PATCH, .apiPath("contacts", "\(alreadyBlockedContact.requireID())", "block")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                #expect(try errorReason(from: res) == "Contact is already blocked")
            }
        }
    }
    
    @Test("block contact success")
    func blockContactSuccess() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let contact = try await createContact(user: currentUser, anotherUser: anotherUser, db: app.db)
            
            try await app.test(.PATCH, .apiPath("contacts", "\(contact.requireID())", "block")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contactResponse = try res.content.decode(ContactResponse.self)
                expect(
                    contact: contactResponse,
                    as: try await anotherUser.toResponse(app: app, directoryPath: testAvatarDirectoryPath),
                    blockedByUserID: try currentUser.requireID()
                )
            }
        }
    }
    
    @Test("unblock contact failure without a token")
    func unblockContactFailureWithoutToken() async throws {
        try await makeApp { app in
            try await app.test(.PATCH, .apiPath("contacts", "1", "unblock")) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("unblock contact failure with an invalid token")
    func unblockContactFailureWithInvalidToken() async throws {
        let invalidToken = "invalid-token"
        
        try await makeApp { app in
            try await app.test(.PATCH, .apiPath("contacts", "1", "unblock")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: invalidToken)
            } afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("unblock contact failure with a non-exist contactID")
    func unblockContactFailureWithNonExistContactID() async throws {
        try await makeApp { app in
            let tokenResponse = try await createTokenResponse(app)
            
            try await app.test(.PATCH, .apiPath("contacts", "1", "unblock")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: tokenResponse.accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .notFound)
                #expect(try errorReason(from: res) == "Contact not found")
            }
        }
    }
    
    @Test("unblock contact failure with an unblocked contact")
    func unblockContactFailureWithUnblockedContact() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let unBlockedContact = try await createContact(user: currentUser, anotherUser: anotherUser, db: app.db)
            
            try await app.test(.PATCH, .apiPath("contacts", "\(unBlockedContact.requireID())", "unblock")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                #expect(try errorReason(from: res) == "Contact is not blocked")
            }
        }
    }
    
    @Test("contact is not blocked by current user, cannot be unblocked")
    func contactNotBlockedByCurrentUser() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let blockedContactByAnotherUser = try await createContact(
                user: currentUser,
                anotherUser: anotherUser,
                blockedByUserID: anotherUser.requireID(),
                db: app.db
            )
            
            try await app.test(
                .PATCH,
                .apiPath("contacts", "\(blockedContactByAnotherUser.requireID())", "unblock")
            ) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                #expect(try errorReason(from: res) == "Contact is not blocked by current user, cannot be unblocked")
            }
        }
    }
    
    @Test("unblock contact success")
    func unblockContactSuccess() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let blockedContactByCurrentUser = try await createContact(
                user: currentUser,
                anotherUser: anotherUser,
                blockedByUserID: currentUser.requireID(),
                db: app.db
            )
            
            try await app.test(
                .PATCH,
                .apiPath("contacts", "\(blockedContactByCurrentUser.requireID())", "unblock")
            ) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contactResponse = try res.content.decode(ContactResponse.self)
                expect(
                    contact: contactResponse,
                    as: try await anotherUser.toResponse(app: app, directoryPath: testAvatarDirectoryPath)
                )
            }
        }
    }
    
    // MARK: - Helpers
    
    private func makeApp(avatarFilename: String = "filename.png",
                         _ test: (Application) async throws -> ()) async throws {
        try await withApp(
            avatarDirectoryPath: testAvatarDirectoryPath,
            avatarFilename: { _ in avatarFilename },
            test
        )
    }
    
    private func expect(contacts: [ContactResponse],
                        as expected: [ContactResponse],
                        sourceLocation: SourceLocation = #_sourceLocation) {
        guard contacts.count == expected.count else {
            Issue.record("Contact count not equal", sourceLocation: sourceLocation)
            return
        }
        
        contacts.enumerated().forEach { index, contact in
            expect(contact: contact, as: expected[index], sourceLocation: sourceLocation)
        }
    }
    
    private func expect(contact: ContactResponse,
                        as expected: ContactResponse,
                        sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(contact.responder.email == expected.responder.email, sourceLocation: sourceLocation)
        #expect(contact.responder.name == expected.responder.name, sourceLocation: sourceLocation)
        #expect(contact.responder.id == expected.responder.id, sourceLocation: sourceLocation)
        #expect(contact.responder.avatarURL == expected.responder.avatarURL, sourceLocation: sourceLocation)
        #expect(contact.blockedByUserID == expected.blockedByUserID, sourceLocation: sourceLocation)
        #expect(contact.unreadMessageCount == expected.unreadMessageCount, sourceLocation: sourceLocation)
        #expect(
            contact.lastUpdate == expected.lastUpdate.removeTimeIntervalDecimal(),
            sourceLocation: sourceLocation
        )
        assert(contact.lastMessage, asExpected: expected.lastMessage, sourceLocation: sourceLocation)
    }
    
    private func assert(_ message: MessageResponse?,
                        asExpected expected: MessageResponse?,
                        sourceLocation: SourceLocation = #_sourceLocation) {
        if message == nil && expected == nil { return }
        guard let message, let expected else {
            Issue.record(
                "Expected message: \(String(describing: expected)), got \(String(describing: message)) instead",
                sourceLocation: sourceLocation
            )
            return
        }
        
        #expect(message.id == expected.id, sourceLocation: sourceLocation)
        #expect(message.text == expected.text, sourceLocation: sourceLocation)
        #expect(message.senderID == expected.senderID, sourceLocation: sourceLocation)
        #expect(message.isRead == expected.isRead, sourceLocation: sourceLocation)
        #expect(
            message.createdAt == expected.createdAt.removeTimeIntervalDecimal(),
            sourceLocation: sourceLocation
        )
    }
    
    private func expect(contact: ContactResponse,
                        as responder: UserResponse,
                        blockedByUserID: Int? = nil,
                        sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(contact.responder.email == responder.email, sourceLocation: sourceLocation)
        #expect(contact.responder.name == responder.name, sourceLocation: sourceLocation)
        #expect(contact.responder.id == responder.id, sourceLocation: sourceLocation)
        #expect(contact.responder.avatarURL == responder.avatarURL, sourceLocation: sourceLocation)
        #expect(contact.blockedByUserID == blockedByUserID, sourceLocation: sourceLocation)
        #expect(contact.unreadMessageCount == 0, sourceLocation: sourceLocation)
    }
    
    private func makeContactDetailForTest(id: Int? = nil,
                                          user: User,
                                          anotherUser: User,
                                          senderID: Int,
                                          text: String,
                                          lastUpdate: Date = .now) -> ContactDetailForTest {
        let messageDetail = ContactDetailForTest.Message(senderID: senderID, text: text, lastUpdate: lastUpdate)
        return ContactDetailForTest(id: id, user: user, anotherUser: anotherUser, messageDetails: [messageDetail])
    }
    
    private func createContactResponses(contactDetails: [ContactDetailForTest],
                                        app: Application) async throws -> [ContactResponse] {
        var contacts = [ContactResponse]()
        for detail in contactDetails {
            contacts.append(try await createContactResponse(
                id: detail.id,
                user: detail.user,
                anotherUser: detail.anotherUser,
                messageDetails: detail.messageDetails,
                app: app
            ))
        }
        return contacts
    }
    
    private func createContactResponse(id: Int? = nil,
                                       user: User,
                                       anotherUser: User,
                                       messageDetails: [ContactDetailForTest.Message] = [],
                                       app: Application) async throws -> ContactResponse {
        let repository = ContactRepository(database: app.db)
        let contact = try await createContact(
            id: id,
            user: user,
            anotherUser: anotherUser,
            messageDetails: messageDetails,
            db: app.db
        )
        
        return try await ContactResponse(
            id: contact.requireID(),
            responder: anotherUser.toResponse(app: app, directoryPath: testAvatarDirectoryPath),
            blockedByUserID: nil,
            unreadMessageCount: repository.unreadMessagesCountFor(contact, senderIsNot: user.requireID()),
            lastUpdate: repository.lastUpdateFor(contact)!,
            lastMessage: repository.lastMessageFor(contact, senderIsNot: user.requireID())?.toResponse()
        )
    }
    
    private func createContact(id: Int? = nil,
                               user: User,
                               anotherUser: User,
                               blockedByUserID: Int? = nil,
                               messageDetails: [ContactDetailForTest.Message] = [],
                               db: Database) async throws -> Contact {
        let contact = try Contact(
            id: id,
            userID1: user.requireID(),
            userID2: anotherUser.requireID(),
            blockedByUserID: blockedByUserID
        )
        try await contact.create(on: db)
        
        let pendingMessages = try messageDetails.map {
            Message(contactID: try contact.requireID(), senderID: $0.senderID, text: $0.text)
        }
        try await contact.$messages.create(pendingMessages, on: db)
        
        // Update createdAt depends on messageDetail.lastUpdate
        let messages = try await contact.$messages.get(on: db)
        for i in 0..<messages.count {
            let message = messages[i]
            message.createdAt = messageDetails[i].lastUpdate
            try await message.update(on: db)
        }
        
        return contact
    }
    
    private struct ContactDetailForTest {
        struct Message {
            let senderID: Int
            let text: String
            let lastUpdate: Date
        }
        
        let id: Int?
        let user: User
        let anotherUser: User
        let messageDetails: [Message]
    }
}

private extension User {
    func toResponse(app: Application, directoryPath: String) async throws -> UserResponse {
        let loader = try AvatarLinkLoader(application: app, directoryPath: directoryPath)
        return try await toResponse { [weak loader] filename in
            guard let filename else { return nil }
            
            return await loader?.get(filename: filename)
        }
    }
}
