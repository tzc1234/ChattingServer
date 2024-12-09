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
        filename: avatarFilename,
        directoryPath: avatarDirectoryPath
    )
    let webSocketStore = WebSocketStore()
    
    private let application: Application
    private let avatarDirectoryPath: String
    private let avatarFilename: @Sendable (String) -> String
    let avatarLinkLoader: AvatarLinkLoader
    private(set) lazy var passwordHasher: UserPasswordHasher = DefaultUserPasswordHasher(application: application)
    
    init(application: Application,
         avatarDirectoryPath: String,
         avatarFilename: @escaping @Sendable (String) -> String,
         passwordHasher: UserPasswordHasher? = nil) throws {
        self.application = application
        self.avatarDirectoryPath = avatarDirectoryPath
        self.avatarFilename = avatarFilename
        self.avatarLinkLoader = try AvatarLinkLoader(application: application, directoryPath: avatarDirectoryPath)
        passwordHasher.map { self.passwordHasher = $0 }
    }
}
