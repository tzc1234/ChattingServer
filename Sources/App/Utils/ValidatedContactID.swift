//
//  ValidatedContactID.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 11/03/2025.
//

import Vapor

struct ValidatedContactID {
    let value: Int
    
    init(_ parameters: Parameters) throws {
        guard let contactIDString = parameters.get("contact_id"), let contactID = Int(contactIDString) else {
            throw ContactError.contactIDInvalid
        }
        
        self.value = contactID
    }
}
