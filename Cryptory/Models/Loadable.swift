import Foundation

enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(String)
}

extension Loadable {
    var value: Value? {
        guard case .loaded(let value) = self else { return nil }
        return value
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var errorMessage: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }
}
