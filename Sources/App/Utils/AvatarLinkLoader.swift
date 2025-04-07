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
    
    func get(filename: String) async -> String? {
        guard FileManager.default.fileExists(atPath: directoryPath + filename) else { return nil }
        
        let baseURL = application.http.server.configuration.hostname
        let port = application.http.server.configuration.port
        let lastComponent = directoryPath.pathComponents.last!.description
        return "http://\(baseURL):\(port)/\(lastComponent)/\(filename)"
    }
}

extension AvatarLinkLoader {
    func avatarLink() -> @Sendable (String?) async -> String? {
        { [weak self] filename in
            guard let filename else { return nil }
            
            return await self?.get(filename: filename)
        }
    }
}
