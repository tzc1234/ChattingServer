//
//  SearchContactsRequest.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 20/06/2025.
//

import Vapor

struct SearchContactsRequest: Content {
    let searchTerm: String
    let before: Date?
    let limit: Int?
    
    enum CodingKeys: String, CodingKey {
        case searchTerm = "search_term"
        case before
        case limit
    }
}
