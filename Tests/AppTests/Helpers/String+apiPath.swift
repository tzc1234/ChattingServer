import Foundation

extension String {
    static func apiPath(_ paths: String...) -> String {
        "api/v1/" + paths.joined(separator: "/")
    }
}
