import Foundation

enum MovieDateParser {
    static func year(from value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value.prefix(4))
    }

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let components = value.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return Calendar(identifier: .gregorian).date(
            from: DateComponents(year: components[0], month: components[1], day: components[2])
        )
    }
}

