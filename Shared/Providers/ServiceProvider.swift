import Foundation

protocol ServiceProvider {
    var serviceId: String { get }
    func fetchSnapshot() async throws -> ServiceSnapshot
}

enum ProviderError: LocalizedError {
    case notImplemented(String)
    case notAuthenticated(String)
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let service):
            return "\(service) provider is not implemented yet."
        case .notAuthenticated(let service):
            return "\(service) requires authentication."
        case .httpError(let code, let service):
            return "\(service) returned HTTP \(code)."
        }
    }
}
