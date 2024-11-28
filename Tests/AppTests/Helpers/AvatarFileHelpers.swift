import Foundation
import Vapor

protocol AvatarFileHelpers {}

extension AvatarFileHelpers {
    func removeUploadedAvatar(filename: String) throws {
        let path = testAvatarDirectoryPath + filename
        guard FileManager.default.fileExists(atPath: path) else { return }
        
        try FileManager.default.removeItem(atPath: path)
    }
    
    var testAvatarDirectoryPath: String {
        let components = URL.temporaryDirectory
            .appending(component: testAvatarDirectory)
            .absoluteString
            .pathComponents
        let directoryPath = components.dropFirst().map(\.description).joined(separator: "/")
        return "/\(directoryPath)/"
    }
    
    var testAvatarDirectory: String {
        "uploaded_avatars"
    }
    
    func avatarFile(_ app: Application) throws -> File {
        let fileURL = URL(fileURLWithPath: testResourceDirectory(app) + "small_avatar.png")
        let fileData = try Data(contentsOf: fileURL)
        return File(data: .init(data: fileData), filename: "small_avatar.png")
    }
    
    func testResourceDirectory(_ app: Application) -> String {
        app.directory.workingDirectory + "Tests/AppTests/Resources/"
    }
}
