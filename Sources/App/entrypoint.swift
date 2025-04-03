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
        let apnsHandler = try DefaultAPNSHandler(
            app: app,
            configuration: APNSConfiguration(
                keyP8FilePath: app.directory.workingDirectory + Environment.get("APNS_KEY_P8_FILE_PATH")!,
                keyID: Environment.get("APNS_KEY_ID")!,
                teamID: Environment.get("APNS_TEAM_ID")!,
                bundleID: Environment.get("APNS_APP_BUNDLE_ID")!,
                environment: Environment.get("APNS_ENVIRONMENT")!
            )
        )
        let dependenciesContainer = try DependenciesContainer(
            application: app,
            avatarDirectoryPath: app.directory.publicDirectory + Constants.AVATARS_DIRECTORY,
            avatarFilenameMaker: { filename in
                let fileExtension = (filename.lowercased() as NSString).pathExtension
                return "\(Date().timeIntervalSince1970).\(fileExtension)"
            },
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
