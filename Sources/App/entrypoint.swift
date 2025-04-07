import Vapor
import Logging
import NIOCore
import NIOPosix

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = try await Application.make(env)
        
        guard let apnsKeyP8FilePath = Environment.get("APNS_KEY_P8_FILE_PATH") else {
            fatalError("APNs key p8 file path not found")
        }
        guard let apnsKeyID = Environment.get("APNS_KEY_ID") else {
            fatalError("APNs key ID not found")
        }
        guard let apnsTeamID = Environment.get("APNS_TEAM_ID") else {
            fatalError("APNs team ID not found")
        }
        guard let appBundleID = Environment.get("APNS_APP_BUNDLE_ID") else {
            fatalError("APNs app bundle ID not found")
        }
        guard let apnsEnvironment = Environment.get("APNS_ENVIRONMENT"),
              ["development", "production"].contains(apnsEnvironment) else {
            fatalError("APNs environment invalid")
        }
        
        let avatarLinkLoader = try AvatarLinkLoader(
            application: app,
            directoryPath: app.directory.publicDirectory + Constants.AVATARS_DIRECTORY
        )
        let apnsHandler = try DefaultAPNSHandler(
            app: app,
            avatarLinkLoader: avatarLinkLoader,
            configuration: APNSConfiguration(
                keyP8FilePath: app.directory.workingDirectory + apnsKeyP8FilePath,
                keyID: apnsKeyID,
                teamID: apnsTeamID,
                bundleID: appBundleID,
                environment: apnsEnvironment
            )
        )
        let dependenciesContainer = try DependenciesContainer(
            application: app,
            avatarDirectoryPath: app.directory.publicDirectory + Constants.AVATARS_DIRECTORY,
            avatarFilenameMaker: { filename in
                let fileExtension = (filename.lowercased() as NSString).pathExtension
                return "\(Date().timeIntervalSince1970).\(fileExtension)"
            },
            avatarLinkLoader: avatarLinkLoader,
            apnsHandler: apnsHandler
        )

        do {
            try await configure(app)
            try routes(app, dependenciesContainer: dependenciesContainer)
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.execute()
        try await app.asyncShutdown()
    }
}
