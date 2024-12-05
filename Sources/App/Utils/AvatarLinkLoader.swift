import Vapor

actor AvatarLinkLoader {
    private let application: Application
    private let directoryPath: String
    
    enum Error: Swift.Error {
        case directoryPathEmpty
    }
    
    init(application: Application, directoryPath: String) throws {
        guard !directoryPath.isEmpty else { throw Error.directoryPathEmpty }
        
        self.application = application
        self.directoryPath = directoryPath
    }
    
    nonisolated func get(filename: String?) -> String? {
        guard let filename else { return nil }
        guard FileManager.default.fileExists(atPath: directoryPath + filename) else { return nil }
        
        let baseURL = application.http.server.configuration.hostname
        let port = application.http.server.configuration.port
        let lastComponent = directoryPath.pathComponents.last!.description
        return "http://\(baseURL):\(port)/\(lastComponent)/\(filename)"
    }
}
