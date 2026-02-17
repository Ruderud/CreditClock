import Foundation

protocol ServiceProvider {
    var serviceId: String { get }
    func fetchSnapshot() async throws -> ServiceSnapshot
}

enum ProviderError: LocalizedError {
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let service):
            return "\(service) provider is not implemented yet."
        }
    }
}
