//
//  RandomGenerator.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 15/11/2024.
//

import Foundation

enum RandomGenerator {
    static func generate(bytes: Int) -> String {
        [UInt8].random(count: bytes).hex
    }
}
