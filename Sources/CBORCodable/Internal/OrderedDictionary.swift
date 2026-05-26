import Foundation

/// Insertion-ordered dictionary used as the backing store for CBOR maps.
///
/// CBOR maps preserve the order in which key/value pairs are written.
/// Round-tripping a non-deterministic CBOR map through this type must
/// return the same byte sequence when re-encoded.
public struct OrderedDictionary<Key: Hashable, Value> {
    public private(set) var keys: [Key]
    public private(set) var values: [Value]
    private var indices: [Key: Int]

    public init() {
        keys = []
        values = []
        indices = [:]
    }

    public init(_ pairs: some Sequence<(Key, Value)>) {
        self.init()
        for (k, v) in pairs { self[k] = v }
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    public subscript(key: Key) -> Value? {
        get {
            guard let i = indices[key] else { return nil }
            return values[i]
        }
        set {
            if let newValue {
                if let i = indices[key] {
                    values[i] = newValue
                } else {
                    indices[key] = keys.count
                    keys.append(key)
                    values.append(newValue)
                }
            } else if let i = indices.removeValue(forKey: key) {
                keys.remove(at: i)
                values.remove(at: i)
                for j in i..<keys.count {
                    indices[keys[j]] = j
                }
            }
        }
    }

    @discardableResult
    public mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
        if let i = indices[key] {
            let old = values[i]
            values[i] = value
            return old
        }
        indices[key] = keys.count
        keys.append(key)
        values.append(value)
        return nil
    }

    public func contains(key: Key) -> Bool { indices[key] != nil }
}

extension OrderedDictionary: Sequence {
    public func makeIterator() -> AnyIterator<(key: Key, value: Value)> {
        var i = 0
        return AnyIterator {
            guard i < self.keys.count else { return nil }
            defer { i += 1 }
            return (self.keys[i], self.values[i])
        }
    }
}

extension OrderedDictionary: Equatable where Value: Equatable {
    public static func == (lhs: OrderedDictionary, rhs: OrderedDictionary) -> Bool {
        lhs.keys == rhs.keys && lhs.values == rhs.values
    }
}

extension OrderedDictionary: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(keys)
        hasher.combine(values)
    }
}

extension OrderedDictionary: Sendable where Key: Sendable, Value: Sendable {}

extension OrderedDictionary: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(elements)
    }
}
