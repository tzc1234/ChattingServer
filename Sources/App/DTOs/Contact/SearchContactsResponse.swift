//
//  SearchContactsResponse.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 20/06/2025.
//

import Vapor

struct SearchContactsResponse: Content {
    let contacts: [ContactResponse]
    let hasMore: Bool
    let total: Int
    
    enum CodingKeys: String, CodingKey {
        case contacts
        case hasMore = "has_more"
        case total
    }
}
