import Fluent
import Vapor

final class DependenciesContainer {
    private var database: Database { application.db }
    
    private(set) lazy var userRepository = UserRepository(database: database)
    private(set) lazy var refreshTokenRepository = RefreshTokenRepository(database: database)
    private(set) lazy var contactRepository = ContactRepository(database: database)
    private(set) lazy var messageRepository = MessageRepository(database: database)
    private(set) lazy var avatarFileSaver = AvatarFileSaver(
        application: application,
        filename: avatarFilenameMaker,
        directoryPath: avatarDirectoryPath
    )
    let webSocketStore = WebSocketStore()
    
    private let application: Application
    private let avatarDirectoryPath: String
    private let avatarFilenameMaker: @Sendable (String) -> String
    let avatarLinkLoader: AvatarLinkLoader
    private(set) lazy var passwordHasher: UserPasswordHasher = DefaultUserPasswordHasher(application: application)
    let apnsHandler: APNSHandler
    
    init(application: Application,
         avatarDirectoryPath: String,
         avatarFilenameMaker: @escaping @Sendable (String) -> String,
         passwordHasher: UserPasswordHasher? = nil,
         apnsHandler: APNSHandler) throws {
        self.application = application
        self.avatarDirectoryPath = avatarDirectoryPath
        self.avatarFilenameMaker = avatarFilenameMaker
        self.avatarLinkLoader = try AvatarLinkLoader(application: application, directoryPath: avatarDirectoryPath)
        self.apnsHandler = apnsHandler
        
        passwordHasher.map { self.passwordHasher = $0 }
    }
}
