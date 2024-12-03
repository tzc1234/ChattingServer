import Foundation

extension Date {
    func adding(seconds: UInt) -> Date {
        self + TimeInterval(seconds)
    }
    
    func reducing(seconds: UInt) -> Date {
        self - TimeInterval(seconds)
    }
    
    func removeTimeIntervalDecimal() -> Date {
        Date(timeIntervalSince1970: TimeInterval(Int(timeIntervalSince1970)))
    }
}
