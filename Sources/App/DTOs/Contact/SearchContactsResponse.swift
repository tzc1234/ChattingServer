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
}
