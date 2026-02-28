import Testing
@testable import OpenClaw

@Suite(.serialized)
@MainActor
struct ConfigStoreTests {
    @Test func loadUsesGateway() async throws {
        var remoteHit = false
        await ConfigStore._testSetOverrides(.init(
            loadRemote: { remoteHit = true; return ["remote": true] }))

        let result = try await ConfigStore.load()

        await ConfigStore._testClearOverrides()
        #expect(remoteHit)
        #expect(result["remote"] as? Bool == true)
    }

    @Test func loadThrowsWhenGatewayUnavailable() async {
        await ConfigStore._testSetOverrides(.init(
            loadRemote: { throw ConfigStore.ConfigError.gatewayUnavailable("test") }))

        do {
            _ = try await ConfigStore.load()
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is ConfigStore.ConfigError)
        }

        await ConfigStore._testClearOverrides()
    }

    @Test func saveSendsToGateway() async throws {
        var remoteHit = false
        await ConfigStore._testSetOverrides(.init(
            saveRemote: { _ in remoteHit = true }))

        try await ConfigStore.save(["test": true])

        await ConfigStore._testClearOverrides()
        #expect(remoteHit)
    }

    @Test func saveThrowsWhenGatewayUnavailable() async {
        await ConfigStore._testSetOverrides(.init(
            saveRemote: { _ in throw ConfigStore.ConfigError.gatewayUnavailable("test") }))

        do {
            try await ConfigStore.save(["test": true])
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is ConfigStore.ConfigError)
        }

        await ConfigStore._testClearOverrides()
    }
}
