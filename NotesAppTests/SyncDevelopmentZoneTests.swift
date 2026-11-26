import Foundation
import CloudKit
import Testing
@testable import NotesAppCore

struct SyncDevelopmentZoneTests {
    private let configuration = SyncCloudInspectionConfiguration(containerIdentifier: "iCloud.heynotes.tests", environment: .development, zoneName: "Notes")

    @Test func unsupportedBuildOrEnvironmentNeverConstructsAClient() async throws {
        let calls = ZoneFactoryCount(), client = ZoneSetupFixture()
        let setup = SyncDevelopmentZoneSetup(transport: { _ in calls.increment(); return client })
        #if DEBUG
        let production = SyncCloudInspectionConfiguration(containerIdentifier: configuration.containerIdentifier, environment: .production, zoneName: "Notes")
        await #expect(throws: SyncDevelopmentZoneError.developmentOnly) { try await setup.prepare(configuration: production) }
        await #expect(throws: SyncActivationError.notConfigured) { try await setup.prepare(configuration: nil) }
        #else
        await #expect(throws: SyncDevelopmentZoneError.developmentOnly) { try await setup.prepare(configuration: configuration) }
        #endif
        #expect(calls.value == 0)
    }

    #if DEBUG
    @Test func preparationDoesNotWriteAndExplicitCreationIsVerifiedAndRepeatable() async throws {
        let client = ZoneSetupFixture()
        let setup = SyncDevelopmentZoneSetup(notifications: NotificationCenter(), transport: { _ in client })
        let plan = try await setup.prepare(configuration: configuration)
        #expect(plan.requiresCreation)
        #expect(await client.creates == 0)
        let outcome = try await setup.createIfNeeded(for: plan)
        if case .created = outcome {} else { Issue.record("Expected a verified creation") }
        let again = try await setup.createIfNeeded(for: plan)
        if case .alreadyExists = again {} else { Issue.record("Repeated setup must reuse the zone") }
        #expect(await client.creates == 1)
    }

    @Test func existingZoneIsNeverRecreatedAfterAnUnreviewedDeletion() async throws {
        let client = ZoneSetupFixture(exists: true)
        let setup = SyncDevelopmentZoneSetup(notifications: NotificationCenter(), transport: { _ in client })
        let plan = try await setup.prepare(configuration: configuration)
        #expect(!plan.requiresCreation)
        await client.setExists(false)
        await #expect(throws: SyncDevelopmentZoneError.planChanged) { try await setup.createIfNeeded(for: plan) }
        #expect(await client.creates == 0)
    }

    @Test func changedAccountOrNotificationRejectsTheWrite() async throws {
        let center = NotificationCenter(), client = ZoneSetupFixture()
        let setup = SyncDevelopmentZoneSetup(notifications: center, transport: { _ in client })
        let plan = try await setup.prepare(configuration: configuration)
        await client.setAccount("another-account")
        await #expect(throws: SyncDevelopmentZoneError.accountChanged) { try await setup.createIfNeeded(for: plan) }
        #expect(await client.creates == 0)
        await client.setAccount(plan.scope.accountRecordName)
        await client.notifyOnProbe(center)
        await #expect(throws: SyncActivationError.accountChanged) { try await setup.createIfNeeded(for: plan) }
        #expect(await client.creates == 0)
    }

    @Test func failedOrUnverifiedCreationIsReportedWithoutCleanupAndCanBeRetried() async throws {
        let client = ZoneSetupFixture()
        let setup = SyncDevelopmentZoneSetup(notifications: NotificationCenter(), transport: { _ in client })
        let plan = try await setup.prepare(configuration: configuration)
        await client.setFailAfterCreation(true)
        await #expect(throws: ZoneSetupFixture.Failure.self) { try await setup.createIfNeeded(for: plan) }
        #expect(await client.creates == 1)
        // Simulate a response lost after server-side creation: retry observes the existing zone.
        let outcome = try await setup.createIfNeeded(for: plan)
        if case .alreadyExists = outcome {} else { Issue.record("Must reuse a possibly successful creation") }
        #expect(await client.creates == 1)
    }

    @Test func cancelledSetupDoesNotCreateAZone() async throws {
        let client = ZoneSetupFixture()
        let setup = SyncDevelopmentZoneSetup(notifications: NotificationCenter(), transport: { _ in client })
        let plan = try await setup.prepare(configuration: configuration)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await setup.createIfNeeded(for: plan)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await client.creates == 0)
    }
    #endif
}

private actor ZoneSetupFixture: SyncDevelopmentZoneTransport {
    struct Failure: Error {}
    private var exists: Bool
    private var account = "development-test-account"
    private var center: NotificationCenter?
    private var failAfterCreation = false
    private(set) var creates = 0
    init(exists: Bool = false) { self.exists = exists }
    func setAccount(_ name: String) { account = name }
    func setExists(_ exists: Bool) { self.exists = exists }
    func notifyOnProbe(_ center: NotificationCenter) { self.center = center }
    func setFailAfterCreation(_ enabled: Bool) { failAfterCreation = enabled }
    func accountRecordName() -> String { account }
    func zoneExists() -> Bool { center?.post(name: .CKAccountChanged, object: nil); return exists }
    func createZone() throws {
        creates += 1; exists = true
        if failAfterCreation { throw Failure() }
    }
}

private final class ZoneFactoryCount: @unchecked Sendable {
    private let lock = NSLock(); private var calls = 0
    var value: Int { lock.withLock { calls } }
    func increment() { lock.withLock { calls += 1 } }
}
