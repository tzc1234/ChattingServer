//
//  SQLQueryStringBuilder.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 06/02/2025.
//

import SQLKit

extension SQLQueryString {
    static func build(@SQLQueryStringBuilder sql: () -> [SQLQueryString]) -> SQLQueryString {
        sql().joined(separator: "\n")
    }
    
    static func withClause(@SQLQueryStringBuilder sql: () -> [SQLQueryString]) -> SQLQueryString {
        "WITH " + sql().joined(separator: ", ")
    }
}

@resultBuilder
enum SQLQueryStringBuilder {
    static func buildBlock(_ components: SQLQueryString...) -> [SQLQueryString] {
        components
    }
}
