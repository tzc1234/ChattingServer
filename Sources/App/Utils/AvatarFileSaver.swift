import Foundation
import Vapor
import NIOCore

actor AvatarFileSaver {
    private let application: Application
    private let filename: (String) -> (String)
    private let directoryPath: String
    
    init(application: Application, filename: @escaping (String) -> String, directoryPath: String) {
        self.application = application
        self.filename = filename
        self.directoryPath = directoryPath
    }
    
    enum Error: Swift.Error {
        case fileTypeNotSupport
        
        var reason: String {
            switch self {
            case .fileTypeNotSupport:
                "Only accept .jpg, .jpeg, or .png files."
            }
        }
    }
    
    func save(_ avatar: File) async throws -> String {
        let filename = avatar.filename
        guard filename.lowercased().hasSuffix(".jpg") ||
             filename.lowercased().hasSuffix(".jpeg") ||
             filename.lowercased().hasSuffix(".png") else {
            throw Error.fileTypeNotSupport
        }
        
        let avatarFilename = self.filename(filename)
        if !FileManager.default.fileExists(atPath: directoryPath) {
            try FileManager.default.createDirectory(
                atPath: directoryPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        let handler = try NIOFileHandle(path: directoryPath + avatarFilename, mode: .write, flags: .allowFileCreation())
        defer { try? handler.close() }
        try await application.fileio.write(fileHandle: handler, buffer: avatar.data)
        
        return avatarFilename
    }
}
