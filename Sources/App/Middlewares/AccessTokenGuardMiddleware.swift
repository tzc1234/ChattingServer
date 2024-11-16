import Vapor

struct AccessTokenGuardMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            _ = try await request.jwt.verify(as: Payload.self)
        } catch {
            throw Abort(.unauthorized, reason: "access token invalid", identifier: "access_token_invalid")
        }
        
        return try await next.respond(to: request)
    }
}
