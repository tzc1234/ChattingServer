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
        let dependenciesContainer = try DependenciesContainer(
            application: app,
            avatarDirectoryPath: app.directory.publicDirectory + Constants.AVATARS_DIRECTORY,
            avatarFilenameMaker: { filename in
                let fileExtension = (filename.lowercased() as NSString).pathExtension
                return "\(Date().timeIntervalSince1970).\(fileExtension)"
            }
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
