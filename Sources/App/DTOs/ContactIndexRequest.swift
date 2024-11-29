import Vapor

struct ContactIndexRequest: Content {
    let beforeContactID: Int?
    let afterContactID: Int?
    let limit: Int?
    
    enum CodingKeys: String, CodingKey {
        case beforeContactID = "before_contact_id"
        case afterContactID = "after_contact_id"
        case limit
    }
}
