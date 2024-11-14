import Fluent
import Vapor

struct TodoDTO: Content {
    let id: UUID?
    let title: String?
    
    func toModel() -> Todo {
        let model = Todo()
        
        model.id = self.id
        if let title = self.title {
            model.title = title
        }
        return model
    }
}
