import CloudKit

enum ICloudAccountAvailability: Equatable, Sendable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unavailable
}

actor ICloudAccountService {
    static let shared = ICloudAccountService()

    private let container: CKContainer

    init(container: CKContainer = CKContainer(identifier: TonightModelContainer.cloudKitContainerIdentifier)) {
        self.container = container
    }

    func availability() async -> ICloudAccountAvailability {
        do {
            let status = try await container.accountStatus()
            return switch status {
            case .available:
                .available
            case .noAccount:
                .noAccount
            case .restricted:
                .restricted
            case .temporarilyUnavailable:
                .temporarilyUnavailable
            case .couldNotDetermine:
                .unavailable
            @unknown default:
                .unavailable
            }
        } catch {
            return .unavailable
        }
    }
}
