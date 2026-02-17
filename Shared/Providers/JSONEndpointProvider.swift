import Foundation

struct JSONEndpointProvider: ServiceProvider {
    let serviceId: String
    private let request: URLRequest
    private let transform: (Data) throws -> ServiceSnapshot

    init(serviceId: String, request: URLRequest, transform: @escaping (Data) throws -> ServiceSnapshot) {
        self.serviceId = serviceId
        self.request = request
        self.transform = transform
    }

    func fetchSnapshot() async throws -> ServiceSnapshot {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try transform(data)
    }
}
