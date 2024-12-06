import Vapor

struct ContactIndexRequest: Content {
    let before: Date?
    let limit: Int?
}
