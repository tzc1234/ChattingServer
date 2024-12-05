@testable import App
import XCTVapor
import Testing
import Fluent
import Vapor

@Suite("Contact routes tests")
struct ContactTests: AppTests, AvatarFileHelpers {
    @Test("new contact failure without token")
    func newContactFailureWithoutToken() async throws {
        try await makeApp { app in
            try await app.test(.POST, .apiPath("contacts")) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("new contact failure with invalid token")
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
    
    @Test("new contact failure with non-exist responder email")
    func newContactFailureWithNonExistResponderEmail() async throws {
        try await makeApp { app in
            let nonExistResponderEmail = "non-exist@email.com"
            let contactRequest = ContactRequest(responderEmail: nonExistResponderEmail)
            let accessToken = try await createUserForTokenResponse(app).accessToken
            
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
            let token = try await createUserForTokenResponse(app)
            let currentUserEmail = token.user.email
            let contactRequest = ContactRequest(responderEmail: currentUserEmail)
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.accessToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .conflict)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Responder cannot be the same as current user")
            }
        }
    }
    
    @Test("new contact success with currentUserID < responderID")
    func mewContactSuccessWithCurrentUserIDSmallerThanResponderID() async throws {
        let avatarFilename = "test-avatar.png"
        try await makeApp(avatarFilename: avatarFilename) { app in
            let currentUserToken = try await createUserForTokenResponse(app)
            let responderToken = try await createUserForTokenResponse(
                app,
                email: "responder@email.com",
                avatar: avatarFile(app)
            )
            let contactRequest = ContactRequest(responderEmail: responderToken.user.email)
            
            try #require(currentUserToken.user.id! < responderToken.user.id!)
            try #require(responderToken.user.avatarURL != nil)
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken.accessToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contact = try res.content.decode(ContactResponse.self)
                expect(contact: contact, as: responderToken.user)
            }
        } afterShutdown: {
            try removeUploadedAvatar(filename: avatarFilename)
        }
    }
    
    @Test("new contact success with currentUserID > responderID")
    func mewContactSuccessWithCurrentUserIDBiggerThanResponderID() async throws {
        let avatarFilename = "test-avatar2.png"
        try await makeApp(avatarFilename: avatarFilename) { app in
            let responderToken = try await createUserForTokenResponse(
                app,
                email: "responder@email.com",
                avatar: avatarFile(app)
            )
            let currentUserToken = try await createUserForTokenResponse(app)
            let contactRequest = ContactRequest(responderEmail: responderToken.user.email)
            
            try #require(currentUserToken.user.id! > responderToken.user.id!)
            try #require(responderToken.user.avatarURL != nil)
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken.accessToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contact = try res.content.decode(ContactResponse.self)
                expect(contact: contact, as: responderToken.user)
            }
        } afterShutdown: {
            try removeUploadedAvatar(filename: avatarFilename)
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
            let currentUserToken = try await createUserForTokenResponse(app)
            
            try await app.test(.GET, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken.accessToken)
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
            let smallerThanBeforeDateContact1 = makeContactDetail(
                id: 100,
                user: currentUser,
                anotherUser: anotherUser1,
                senderID: try currentUser.requireID(),
                lastUpdate: beforeDate.reducing(seconds: 1)
            )
            let equalToBeforeDateContact = makeContactDetail(
                id: 200,
                user: currentUser,
                anotherUser: anotherUser2,
                senderID: try anotherUser2.requireID(),
                lastUpdate: beforeDate
            )
            let greaterThanBeforeDateContact = makeContactDetail(
                id: 300,
                user: currentUser,
                anotherUser: anotherUser3,
                senderID: try anotherUser3.requireID(),
                lastUpdate: beforeDate.adding(seconds: 1)
            )
            let smallerThanBeforeDateContact2 = makeContactDetail(
                id: 400,
                user: currentUser,
                anotherUser: anotherUser4,
                senderID: try anotherUser4.requireID(),
                lastUpdate: beforeDate.reducing(seconds: 1)
            )
            let nonCurrentUserContact = makeContactDetail(
                id: 500,
                user: anotherUser1,
                anotherUser: anotherUser2,
                senderID: try anotherUser1.requireID(),
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
    
    @Test("block contact failure with an non-exist contactID")
    func blockContactFailureWithNonExistContactID() async throws {
        try await makeApp { app in
            let currentUserToken = try await createUserForTokenResponse(app)
            
            try await app.test(.PATCH, .apiPath("contacts", "1", "block")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken.accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .notFound)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Contact not found")
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
                app: app
            )
            
            try await app.test(.PATCH, .apiPath("contacts", "\(alreadyBlockedContact.requireID())", "block")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Contact is already blocked")
            }
        }
    }
    
    @Test("block contact success")
    func blockContactSuccess() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let contact = try await createContact(user: currentUser, anotherUser: anotherUser, app: app)
            
            try await app.test(.PATCH, .apiPath("contacts", "\(contact.requireID())", "block")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contactResponse = try res.content.decode(ContactResponse.self)
                expect(
                    contact: contactResponse,
                    as: anotherUser.toResponse(app: app, avatarDirectoryPath: testAvatarDirectoryPath),
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
    
    @Test("unblock contact failure with an non-exist contactID")
    func unblockContactFailureWithNonExistContactID() async throws {
        try await makeApp { app in
            let currentUserToken = try await createUserForTokenResponse(app)
            
            try await app.test(.PATCH, .apiPath("contacts", "1", "unblock")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken.accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .notFound)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Contact not found")
            }
        }
    }
    
    @Test("unblock contact failure with an unblocked contact")
    func unblockContactFailureWithUnblockedContact() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let unBlockedContact = try await createContact(user: currentUser, anotherUser: anotherUser, app: app)
            
            try await app.test(.PATCH, .apiPath("contacts", "\(unBlockedContact.requireID())", "unblock")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Contact is not blocked")
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
                app: app
            )
            
            try await app.test(
                .PATCH,
                .apiPath("contacts", "\(blockedContactByAnotherUser.requireID())", "unblock")
            ) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Contact is not blocked by current user, cannot be unblocked")
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
                app: app
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
                    as: anotherUser.toResponse(app: app, avatarDirectoryPath: testAvatarDirectoryPath)
                )
            }
        }
    }
    
    // MARK: - Helpers
    
    private func makeApp(avatarFilename: String = "filename.png",
                         _ test: (Application) async throws -> (),
                         afterShutdown: () throws -> Void = {}) async throws {
        try await withApp(
            avatarFilename: { _ in avatarFilename },
            avatarDirectoryPath: { testAvatarDirectoryPath },
            webSocketStore: WebSocketStore(),
            test,
            afterShutdown: afterShutdown
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
            Int(contact.lastUpdate.timeIntervalSince1970) == Int(expected.lastUpdate.timeIntervalSince1970),
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
    
    private func makeContactDetail(id: Int? = nil,
                                   user: User,
                                   anotherUser: User,
                                   senderID: Int,
                                   text: String = "any text",
                                   lastUpdate: Date = .now) -> ContactDetail {
        let messageDetail = MessageDetail(senderID: senderID, text: text, lastUpdate: lastUpdate)
        return ContactDetail(id: id, user: user, anotherUser: anotherUser, messageDetails: [messageDetail])
    }
    
    private func createContactResponses(contactDetails: [ContactDetail],
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
                                       messageDetails: [MessageDetail] = [],
                                       app: Application) async throws -> ContactResponse {
        let contact = try await createContact(
            id: id,
            user: user,
            anotherUser: anotherUser,
            messageDetails: messageDetails,
            app: app
        )
        let repository = ContactRepository(database: app.db)
        
        return ContactResponse(
            id: try contact.requireID(),
            responder: anotherUser.toResponse(app: app, avatarDirectoryPath: testAvatarDirectoryPath),
            blockedByUserID: nil,
            unreadMessageCount: try await repository.unreadMessagesCountFor(contact, senderIsNot: user.id!),
            lastUpdate: try await repository.lastUpdateFrom(contact)!
        )
    }
    
    private func createContact(id: Int? = nil,
                               user: User,
                               anotherUser: User,
                               blockedByUserID: Int? = nil,
                               messageDetails: [MessageDetail] = [],
                               app: Application) async throws -> Contact {
        let contact = try Contact(
            id: id,
            userID1: user.requireID(),
            userID2: anotherUser.requireID(),
            blockedByUserID: blockedByUserID
        )
        try await contact.create(on: app.db)
        
        let pendingMessages = try messageDetails.map {
            Message(contactID: try contact.requireID(), senderID: $0.senderID, text: $0.text)
        }
        try await contact.$messages.create(pendingMessages, on: app.db)
        
        // Update createdAt depends on messageDetail.lastUpdate
        let messages = try await contact.$messages.get(on: app.db)
        for i in 0..<messages.count {
            let message = messages[i]
            message.createdAt = messageDetails[i].lastUpdate
            try await message.update(on: app.db)
        }
        
        return contact
    }
    
    private struct MessageDetail {
        let senderID: Int
        let text: String
        let lastUpdate: Date
    }
    
    private struct ContactDetail {
        let id: Int?
        let user: User
        let anotherUser: User
        let messageDetails: [MessageDetail]
    }
}
