//
//  MessageChannelContactValidationMiddleware.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 19/12/2024.
//

import Vapor

struct MessageChannelContactValidationMiddleware: AsyncMiddleware {
    let contactRepository: ContactRepository
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let contactID = try validateContactID(request)
        let userID = try request.auth.require(Payload.self).userID
        
        guard let contact = try await contactRepository.findBy(id: contactID, userID: userID) else {
            throw MessageError.contactNotFound
        }
        
        guard contact.$blockedBy.id == nil else {
            throw MessageError.contactIsBlocked
        }
        
        return try await next.respond(to: request)
    }
    
    private func validateContactID(_ req: Request) throws -> ContactID {
        guard let contactIDString = req.parameters.get("contact_id"), let contactID = Int(contactIDString) else {
            throw MessageError.contactIDInvalid
        }
        
        return contactID
    }
}
