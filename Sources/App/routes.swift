import Fluent
import Vapor

func routes(_ app: Application, dependenciesContainer: DependenciesContainer) throws {
    app.get { req async in
        "It works!"
    }
    
    try app.group("api", "v1") { routes in
        try routes.register(collection: AuthenticationController(
            userRepository: dependenciesContainer.userRepository,
            refreshTokenRepository: dependenciesContainer.refreshTokenRepository,
            avatarFileSaver: dependenciesContainer.avatarFileSaver,
            avatarLinkLoader: dependenciesContainer.avatarLinkLoader,
            passwordHasher: dependenciesContainer.passwordHasher
        ))
        try routes.register(collection: ContactController(
            contactRepository: dependenciesContainer.contactRepository,
            userRepository: dependenciesContainer.userRepository,
            avatarLinkLoader: dependenciesContainer.avatarLinkLoader,
            apnsHandler: dependenciesContainer.apnsHandler
        ))
        try routes.register(collection: MessageController(
            contactRepository: dependenciesContainer.contactRepository,
            messageRepository: dependenciesContainer.messageRepository,
            webSocketStore: dependenciesContainer.webSocketStore
        ))
    }
}
