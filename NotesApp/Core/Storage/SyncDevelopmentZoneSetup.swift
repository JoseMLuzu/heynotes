import Foundation

struct SyncDevelopmentZonePlan: Sendable {
    let id: UUID
    let scope: SyncAccountScope
    let requiresCreation: Bool
    fileprivate let configuration: SyncCloudInspectionConfiguration
}

enum SyncDevelopmentZoneOutcome: Sendable { case alreadyExists, created }

/// Explicit developer-only setup: prepare is read-only; createIfNeeded is the
/// separate write action. Neither is installed into app launch or the settings UI.
struct SyncDevelopmentZoneSetup: Sendable {
    private let notifications: NotificationCenter
    private let transport: @Sendable (SyncCloudInspectionConfiguration) throws -> any SyncDevelopmentZoneTransport

    init(notifications: NotificationCenter = .default,
         transport: @escaping @Sendable (SyncCloudInspectionConfiguration) throws -> any SyncDevelopmentZoneTransport = {
             try CloudKitDevelopmentZoneTransport(configuration: $0)
         }) {
        self.notifications = notifications; self.transport = transport
    }

    func prepare(configuration: SyncCloudInspectionConfiguration?) async throws -> SyncDevelopmentZonePlan {
        let configuration = try requireDevelopment(configuration)
        try Task.checkCancellation()
        let watch = SyncAccountChangeWatch(center: notifications), client = try transport(configuration)
        let name = try await client.accountRecordName()
        let scope = try SyncAccountScope(containerIdentifier: configuration.containerIdentifier, environment: configuration.environment,
            accountRecordName: name, zone: configuration.zoneID)
        try watch.check()
        let exists = try await client.zoneExists()
        guard try await client.accountRecordName() == name else { throw SyncDevelopmentZoneError.accountChanged }
        try watch.check(); try Task.checkCancellation()
        return SyncDevelopmentZonePlan(id: UUID(), scope: scope, requiresCreation: !exists, configuration: configuration)
    }

    /// Call only for a reviewed setup plan after explicit developer confirmation.
    /// A failure after createZone begins may mean the zone was created: verify/retry,
    /// never attempt to roll back by deleting a zone or any user's records.
    func createIfNeeded(for plan: SyncDevelopmentZonePlan) async throws -> SyncDevelopmentZoneOutcome {
        let configuration = try requireDevelopment(plan.configuration)
        try Task.checkCancellation()
        let watch = SyncAccountChangeWatch(center: notifications), client = try transport(configuration)
        func verifyAccount() async throws {
            guard try await client.accountRecordName() == plan.scope.accountRecordName else { throw SyncDevelopmentZoneError.accountChanged }
            try watch.check(); try Task.checkCancellation()
        }
        try await verifyAccount()
        if try await client.zoneExists() {
            try await verifyAccount(); return .alreadyExists
        }
        guard plan.requiresCreation else { throw SyncDevelopmentZoneError.planChanged }
        try await verifyAccount()
        try await client.createZone()
        try await verifyAccount()
        guard try await client.zoneExists() else { throw SyncDevelopmentZoneError.invalidResult }
        try await verifyAccount()
        return .created
    }

    private func requireDevelopment(_ configuration: SyncCloudInspectionConfiguration?) throws -> SyncCloudInspectionConfiguration {
        #if DEBUG
        guard let configuration else { throw SyncActivationError.notConfigured }
        try configuration.validate()
        guard configuration.environment == .development else { throw SyncDevelopmentZoneError.developmentOnly }
        return configuration
        #else
        throw SyncDevelopmentZoneError.developmentOnly
        #endif
    }
}

enum SyncDevelopmentZoneError: LocalizedError, Equatable {
    case developmentOnly, accountChanged, planChanged, invalidResult
    var errorDescription: String? {
        switch self {
        case .developmentOnly: "This setup helper requires a Debug build configured for the development CloudKit environment."
        case .accountChanged: "The account changed during zone setup. Verify the zone in the selected account before retrying."
        case .planChanged: "The zone changed after inspection. Review a fresh setup plan before creating it."
        case .invalidResult: "The zone setup result could not be verified. Inspect the selected account before retrying."
        }
    }
}
