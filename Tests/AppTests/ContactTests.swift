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
        let invalidToken = "invalid-valid-token"
        
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
        let invalidToken = "invalid-valid-token"
        
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
                try req.content.encode(ContactIndexRequest(beforeContactID: nil, afterContactID: nil, limit: nil))
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
            let currentUserToken = try await createUserForTokenResponse(app)
            let currentUser = try #require(try await User.find(currentUserToken.user.id!, on: app.db))
            let anotherUser = try await createUser(app, email: "another@email.com")
            let expectedContactResponse = try await createContactResponse(
                user: currentUser,
                anotherUser: anotherUser,
                app: app
            )
            
            try await app.test(.GET, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken.accessToken)
                try req.content.encode(ContactIndexRequest(beforeContactID: nil, afterContactID: nil, limit: nil))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contactsResponse = try res.content.decode(ContactsResponse.self)
                #expect(contactsResponse.contacts == [expectedContactResponse])
            }
        }
    }
    
    @Test("get multiple contacts before a contact ID")
    func getMultipleContactsBeforeContactID() async throws {
        try await makeApp { app in
            let currentUserToken = try await createUserForTokenResponse(app)
            let currentUser = try #require(try await User.find(currentUserToken.user.id!, on: app.db))
            let anotherUser1 = try await createUser(app, email: "another-user1@email.com")
            let anotherUser2 = try await createUser(app, email: "another-user2@email.com")
            let anotherUser3 = try await createUser(app, email: "another-user3@email.com")
            let anotherUser4 = try await createUser(app, email: "another-user4@email.com")
            let anotherUser5 = try await createUser(app, email: "another-user5@email.com")
            
            let contactResponses = try await createContactResponses(
                userPairs: [
                    (currentUser, anotherUser1), // contactID: 1
                    (currentUser, anotherUser2), // contactID: 2
                    (currentUser, anotherUser3), // contactID: 3
                    (currentUser, anotherUser4), // contactID: 4
                    (currentUser, anotherUser5), // contactID: 5
                ],
                app: app
            )
            let beforeContactID = 5
            let limit = 3
            let expectedContactResponses = Array(contactResponses
                .filter({ $0.id < beforeContactID })
                .sorted(by: { $0.id > $1.id })[..<limit])
            
            try await app.test(.GET, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken.accessToken)
                try req.content.encode(ContactIndexRequest(
                    beforeContactID: beforeContactID,
                    afterContactID: nil,
                    limit: limit
                ))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contactsResponse = try res.content.decode(ContactsResponse.self)
                #expect(contactsResponse.contacts == expectedContactResponses)
            }
        }
    }
    
    @Test("get multiple contacts after a contact ID")
    func getMultipleContactsAfterContactID() async throws {
        try await makeApp { app in
            let currentUserToken = try await createUserForTokenResponse(app)
            let currentUser = try #require(try await User.find(currentUserToken.user.id!, on: app.db))
            let anotherUser1 = try await createUser(app, email: "another-user1@email.com")
            let anotherUser2 = try await createUser(app, email: "another-user2@email.com")
            let anotherUser3 = try await createUser(app, email: "another-user3@email.com")
            let anotherUser4 = try await createUser(app, email: "another-user4@email.com")
            let anotherUser5 = try await createUser(app, email: "another-user5@email.com")
            
            let contactResponses = try await createContactResponses(
                userPairs: [
                    (currentUser, anotherUser1), // contactID: 1
                    (currentUser, anotherUser2), // contactID: 2
                    (currentUser, anotherUser3), // contactID: 3
                    (currentUser, anotherUser4), // contactID: 4
                    (currentUser, anotherUser5), // contactID: 5
                ],
                app: app
            )
            let afterContactID = 1
            let limit = 3
            let expectedContactResponses = Array(contactResponses
                .filter({ $0.id > afterContactID })
                .sorted(by: { $0.id > $1.id })[..<limit])
            
            try await app.test(.GET, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken.accessToken)
                try req.content.encode(ContactIndexRequest(
                    beforeContactID: nil,
                    afterContactID: afterContactID,
                    limit: limit
                ))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let contactsResponse = try res.content.decode(ContactsResponse.self)
                #expect(contactsResponse.contacts == expectedContactResponses)
            }
        }
    }
    
    @Test("block contact failure without token")
    @Test("block contact failure without a token")
    func blockContactFailureWithoutToken() async throws {
        try await makeApp { app in
            try await app.test(.PATCH, .apiPath("contacts", ":contact_id", "block")) { res async throws in
                #expect(res.status == .unauthorized)
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
    
    private func expect(contact: ContactResponse,
                        as responder: UserResponse,
                        sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(contact.responder.email == responder.email, sourceLocation: sourceLocation)
        #expect(contact.responder.name == responder.name, sourceLocation: sourceLocation)
        #expect(contact.responder.id == responder.id, sourceLocation: sourceLocation)
        #expect(contact.responder.avatarURL == responder.avatarURL, sourceLocation: sourceLocation)
        #expect(contact.blockedByUserID == nil, sourceLocation: sourceLocation)
        #expect(contact.unreadMessageCount == 0, sourceLocation: sourceLocation)
    }
    
    private func createUser(_ app: Application,
                            name: String = "a username",
                            email: String = "a@email.com",
                            password: String = "aPassword") async throws -> User {
        let user = User(name: name, email: email, password: password)
        try await user.save(on: app.db)
        return user
    }
    
    private func createContactResponses(userPairs: [(user: User, anotherUser: User)],
                                        app: Application) async throws -> [ContactResponse] {
        var contacts = [ContactResponse]()
        for pair in userPairs {
            contacts.append(try await createContactResponse(user: pair.user, anotherUser: pair.anotherUser, app: app))
        }
        return contacts
    }
    
    private func createContactResponse(user: User,
                                       anotherUser: User,
                                       app: Application) async throws -> ContactResponse {
        let contact = try Contact(userID1: user.requireID(), userID2: anotherUser.requireID())
        try await contact.create(on: app.db)
        
        return ContactResponse(
            id: contact.id!,
            responder: anotherUser.toResponse(app: app, avatarDirectoryPath: testAvatarDirectoryPath),
            blockedByUserID: nil,
            unreadMessageCount: 0
        )
    }
    
    private func createUserForTokenResponse(_ app: Application,
                                            name: String = "a username",
                                            email: String = "a@email.com",
                                            password: String = "aPassword",
                                            avatar: File? = nil) async throws -> TokenResponse {
        let registerRequest = RegisterRequest(name: name, email: email, password: password, avatar: avatar)
        var tokenResponse: TokenResponse?
        
        try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
            try req.content.encode(registerRequest)
        }, afterResponse: { res async throws in
            tokenResponse = try res.content.decode(TokenResponse.self)
        })
        
        return tokenResponse!
    }
}
