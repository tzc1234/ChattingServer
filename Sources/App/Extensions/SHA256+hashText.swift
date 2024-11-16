import Vapor

extension SHA256 {
    static func hash(_ text: String) -> String {
        Self.hash(data: Data(text.utf8)).hex
    }
}

