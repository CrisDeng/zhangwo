import Foundation
import Observation

@MainActor
@Observable
final class GatewayProcessManager {
    static let shared = GatewayProcessManager()

    enum Status: Equatable {
        case stopped
        case starting
        case running(details: String?)
        case attachedExisting(details: String?)
        case failed(String)

        var label: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting…"
            case let .running(details):
                if let details, !details.isEmpty { return "Running (\(details))" }
                return "Running"
            case let .attachedExisting(details):
                if let details, !details.isEmpty {
                    return "Using existing gateway (\(details))"
                }
                return "Using existing gateway"
            case let .failed(reason): return "Failed: \(reason)"
            }
        }
    }

    private(set) var status: Status = .stopped {
        didSet { CanvasManager.shared.refreshDebugStatus() }
    }

    private(set) var log: String = ""
    private(set) var environmentStatus: GatewayEnvironmentStatus = .checking
    private(set) var existingGatewayDetails: String?
    private(set) var lastFailureReason: String?
    private var desiredActive = false
    private var environmentRefreshTask: Task<Void, Never>?
    private var lastEnvironmentRefresh: Date?
    private var logRefreshTask: Task<Void, Never>?
    #if DEBUG
    private var testingConnection: GatewayConnection?
    #endif
    private let logger = Logger(subsystem: "ai.openclaw", category: "gateway.process")

    private let logLimit = 20000 // characters to keep in-memory
    private let environmentRefreshMinInterval: TimeInterval = 30
    private var connection: GatewayConnection {
        #if DEBUG
        return self.testingConnection ?? .shared
        #else
        return .shared
        #endif
    }

    func setActive(_ active: Bool) {
        self.logger.info("setActive called: active=\(active), currentStatus=\(self.status)")
        // Remote mode should never spawn a local gateway; treat as stopped.
        if CommandResolver.connectionModeIsRemote() {
            self.desiredActive = false
            self.stop()
            self.status = .stopped
            self.appendLog("[gateway] remote mode active; skipping local gateway\n")
            self.logger.info("gateway process skipped: remote mode active")
            return
        }
        self.logger.info("gateway active requested active=\(active)")
        self.desiredActive = active
        self.refreshEnvironmentStatus()
        if active {
            self.logger.info("Calling startIfNeeded()")
            self.startIfNeeded()
        } else {
            self.logger.info("Calling stop()")
            self.stop()
        }
    }

    func ensureLaunchAgentEnabledIfNeeded() async {
        guard !CommandResolver.connectionModeIsRemote() else { return }
        if GatewayLaunchAgentManager.isLaunchAgentWriteDisabled() {
            self.appendLog("[gateway] launchd auto-enable skipped (attach-only)\n")
            self.logger.info("gateway launchd auto-enable skipped (disable marker set)")
            return
        }
        
        let enabled = await GatewayLaunchAgentManager.isLoaded()
        let needsBindUpdate = GatewayLaunchAgentManager.needsBindModeUpdate()
        
        // If daemon is already enabled but bind mode needs update, reinstall it
        if enabled && needsBindUpdate {
            self.logger.info("daemon bind mode update needed, reinstalling")
            self.appendLog("[gateway] updating launchd job bind mode to lan\n")
            let bundlePath = Bundle.main.bundleURL.path
            let port = GatewayEnvironment.gatewayPort()
            let err = await GatewayLaunchAgentManager.set(enabled: true, bundlePath: bundlePath, port: port)
            if let err {
                self.appendLog("[gateway] launchd bind mode update failed: \(err)\n")
            } else {
                self.appendLog("[gateway] launchd bind mode updated successfully\n")
            }
            return
        }
        
        guard !enabled else { return }
        let bundlePath = Bundle.main.bundleURL.path
        let port = GatewayEnvironment.gatewayPort()
        self.appendLog("[gateway] auto-enabling launchd job (\(gatewayLaunchdLabel)) on port \(port)\n")
        let err = await GatewayLaunchAgentManager.set(enabled: true, bundlePath: bundlePath, port: port)
        if let err {
            self.appendLog("[gateway] launchd auto-enable failed: \(err)\n")
        }
    }

    func startIfNeeded() {
        self.logger.info("startIfNeeded called: desiredActive=\(self.desiredActive), currentStatus=\(self.status)")
        guard self.desiredActive else {
            self.logger.info("startIfNeeded skipped: desiredActive is false")
            return
        }
        // Do not spawn in remote mode (the gateway should run on the remote host).
        guard !CommandResolver.connectionModeIsRemote() else {
            self.logger.info("startIfNeeded skipped: remote mode detected")
            self.status = .stopped
            return
        }
        // Many surfaces can call `setActive(true)` in quick succession (startup, Canvas, health checks).
        // Avoid spawning multiple concurrent "start" tasks that can thrash launchd and flap the port.
        switch self.status {
        case .starting, .running, .attachedExisting:
            self.logger.info("startIfNeeded skipped: already in active state \(self.status)")
            return
        case .stopped, .failed:
            self.logger.info("startIfNeeded proceeding: current state is \(self.status)")
            break
        }
        self.status = .starting
        self.logger.info("gateway start requested, status set to .starting")

        // First try to latch onto an already-running gateway to avoid spawning a duplicate.
        Task { [weak self] in
            guard let self else { return }
            self.logger.info("Starting gateway attachment process")
            if await self.attachExistingGatewayIfAvailable() {
                self.logger.info("Successfully attached to existing gateway")
                return
            }
            self.logger.info("No existing gateway found, enabling launchd gateway")
            await self.enableLaunchdGateway()
        }
    }

    func stop() {
        self.desiredActive = false
        self.existingGatewayDetails = nil
        self.lastFailureReason = nil
        self.status = .stopped
        self.logger.info("gateway stop requested")
        if CommandResolver.connectionModeIsRemote() {
            return
        }
        let bundlePath = Bundle.main.bundleURL.path
        Task {
            _ = await GatewayLaunchAgentManager.set(
                enabled: false,
                bundlePath: bundlePath,
                port: GatewayEnvironment.gatewayPort())
        }
    }

    func clearLastFailure() {
        self.lastFailureReason = nil
    }

    func refreshEnvironmentStatus(force: Bool = false) {
        let now = Date()
        if !force {
            if self.environmentRefreshTask != nil { return }
            if let last = self.lastEnvironmentRefresh,
               now.timeIntervalSince(last) < self.environmentRefreshMinInterval
            {
                return
            }
        }
        self.lastEnvironmentRefresh = now
        self.environmentRefreshTask = Task { [weak self] in
            let status = await Task.detached(priority: .utility) {
                GatewayEnvironment.check()
            }.value
            await MainActor.run {
                guard let self else { return }
                self.environmentStatus = status
                self.environmentRefreshTask = nil
            }
        }
    }

    func refreshLog() {
        guard self.logRefreshTask == nil else { return }
        let path = GatewayLaunchAgentManager.launchdGatewayLogPath()
        let limit = self.logLimit
        self.logRefreshTask = Task { [weak self] in
            let log = await Task.detached(priority: .utility) {
                Self.readGatewayLog(path: path, limit: limit)
            }.value
            await MainActor.run {
                guard let self else { return }
                if !log.isEmpty {
                    self.log = log
                }
                self.logRefreshTask = nil
            }
        }
    }

    // MARK: - Internals

    /// Attempt to connect to an already-running gateway on the configured port.
    /// If successful, mark status as attached and skip spawning a new process.
    private func attachExistingGatewayIfAvailable() async -> Bool {
        let port = GatewayEnvironment.gatewayPort()
        self.logger.info("Checking for existing gateway on port \(port)")
        
        let instance = await PortGuardian.shared.describe(port: port)
        let instanceText = instance.map { self.describe(instance: $0) }
        let hasListener = instance != nil
        
        self.logger.info("Port \(port) status: hasListener=\(hasListener), instance=\(instanceText ?? "none")")

        let attemptAttach = {
            try await self.connection.requestRaw(method: .health, timeoutMs: 2000)
        }

        let maxAttempts = hasListener ? 3 : 1
        for attempt in 0..<maxAttempts {
            self.logger.info("Gateway connection attempt \(attempt + 1)/\(maxAttempts)")
            do {
                let data = try await attemptAttach()
                self.logger.info("Gateway health check succeeded on attempt \(attempt + 1)")
                let snap = decodeHealthSnapshot(from: data)
                let details = self.describe(details: instanceText, port: port, snap: snap)
                self.existingGatewayDetails = details
                self.clearLastFailure()
                self.status = .attachedExisting(details: details)
                self.appendLog("[gateway] using existing instance: \(details)\n")
                self.logger.info("Successfully attached to existing gateway: \(details)")
                self.refreshControlChannelIfNeeded(reason: "attach existing")
                self.refreshLog()
                return true
            } catch {
                self.logger.warning("Gateway connection attempt \(attempt + 1) failed: \(error.localizedDescription)")
                if attempt < 2, hasListener {
                    self.logger.info("Retrying connection after delay...")
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }

                if hasListener {
                    let reason = self.describeAttachFailure(error, port: port, instance: instance)
                    self.existingGatewayDetails = instanceText
                    self.status = .failed(reason)
                    self.lastFailureReason = reason
                    self.appendLog("[gateway] existing listener on port \(port) but attach failed: \(reason)\n")
                    self.logger.warning("Gateway attach failed after all attempts: \(reason)")
                    return true
                }

                // No reachable gateway (and no listener) — fall through to spawn.
                self.logger.info("No gateway listener found on port \(port), proceeding to spawn new gateway")
                self.existingGatewayDetails = nil
                return false
            }
        }

        self.logger.info("All gateway connection attempts exhausted")
        self.existingGatewayDetails = nil
        return false
    }

    private func describe(details instance: String?, port: Int, snap: HealthSnapshot?) -> String {
        let instanceText = instance ?? "pid unknown"
        if let snap {
            let order = snap.channelOrder ?? Array(snap.channels.keys)
            let linkId = order.first(where: { snap.channels[$0]?.linked == true })
                ?? order.first(where: { snap.channels[$0]?.linked != nil })
            guard let linkId else {
                return "port \(port), health probe succeeded, \(instanceText)"
            }
            let linked = snap.channels[linkId]?.linked ?? false
            let authAge = snap.channels[linkId]?.authAgeMs.flatMap(msToAge) ?? "unknown age"
            let label =
                snap.channelLabels?[linkId] ??
                linkId.capitalized
            let linkText = linked ? "linked" : "not linked"
            return "port \(port), \(label) \(linkText), auth \(authAge), \(instanceText)"
        }
        return "port \(port), health probe succeeded, \(instanceText)"
    }

    private func describe(instance: PortGuardian.Descriptor) -> String {
        let path = instance.executablePath ?? "path unknown"
        return "pid \(instance.pid) \(instance.command) @ \(path)"
    }

    private func describeAttachFailure(_ error: Error, port: Int, instance: PortGuardian.Descriptor?) -> String {
        let ns = error as NSError
        let message = ns.localizedDescription.isEmpty ? "unknown error" : ns.localizedDescription
        let lower = message.lowercased()
        if self.isGatewayAuthFailure(error) {
            return """
            Gateway on port \(port) rejected auth. Set gateway.auth.token to match the running gateway \
            (or clear it on the gateway) and retry.
            """
        }
        if lower.contains("protocol mismatch") {
            return "Gateway on port \(port) is incompatible (protocol mismatch). Update the app/gateway."
        }
        if lower.contains("unexpected response") || lower.contains("invalid response") {
            return "Port \(port) returned non-gateway data; another process is using it."
        }
        if let instance {
            let instanceText = self.describe(instance: instance)
            return "Gateway listener found on port \(port) (\(instanceText)) but health check failed: \(message)"
        }
        return "Gateway listener found on port \(port) but health check failed: \(message)"
    }

    private func isGatewayAuthFailure(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .dataNotAllowed {
            return true
        }
        let ns = error as NSError
        if ns.domain == "Gateway", ns.code == 1008 { return true }
        let lower = ns.localizedDescription.lowercased()
        return lower.contains("unauthorized") || lower.contains("auth")
    }

    private func enableLaunchdGateway() async {
        self.logger.info("Starting launchd gateway startup process")
        self.existingGatewayDetails = nil
        
        self.logger.info("Resolving gateway command configuration")
        let resolution = await Task.detached(priority: .utility) {
            GatewayEnvironment.resolveGatewayCommand()
        }.value
        await MainActor.run { self.environmentStatus = resolution.status }
        guard resolution.command != nil else {
            self.logger.error("Gateway command resolution failed: \(resolution.status.message)")
            await MainActor.run {
                self.status = .failed(resolution.status.message)
            }
            return
        }
        self.logger.info("Gateway command resolved successfully")

        if GatewayLaunchAgentManager.isLaunchAgentWriteDisabled() {
            let message = "Launchd disabled; start the Gateway manually or disable attach-only."
            self.status = .failed(message)
            self.lastFailureReason = "launchd disabled"
            self.appendLog("[gateway] launchd disabled; skipping auto-start\n")
            self.logger.warning("Gateway launchd startup skipped: launchd disabled marker set")
            return
        }

        let bundlePath = Bundle.main.bundleURL.path
        let port = GatewayEnvironment.gatewayPort()
        self.logger.info("Configuring launchd gateway: bundlePath=\(bundlePath), port=\(port)")
        self.appendLog("[gateway] enabling launchd job (\(gatewayLaunchdLabel)) on port \(port)\n")
        
        let err = await GatewayLaunchAgentManager.set(enabled: true, bundlePath: bundlePath, port: port)
        if let err {
            self.logger.error("Gateway launchd enable failed: \(err)")
            self.status = .failed(err)
            self.lastFailureReason = err
            return
        }
        self.logger.info("Gateway launchd service enabled successfully")

        // Best-effort: wait for the gateway to accept connections.
        self.logger.info("Waiting for gateway to start accepting connections (timeout: 6 seconds)")
        let deadline = Date().addingTimeInterval(6)
        var attemptCount = 0
        while Date() < deadline {
            attemptCount += 1
            if !self.desiredActive {
                self.logger.info("Gateway startup cancelled: desiredActive became false")
                return
            }
            do {
                self.logger.info("Gateway health check attempt \(attemptCount)")
                _ = try await self.connection.requestRaw(method: .health, timeoutMs: 1500)
                self.logger.info("Gateway health check succeeded on attempt \(attemptCount)")
                let instance = await PortGuardian.shared.describe(port: port)
                let details = instance.map { "pid \($0.pid)" }
                self.clearLastFailure()
                self.status = .running(details: details)
                self.logger.info("Gateway successfully started: details=\(details ?? "ok")")
                self.refreshControlChannelIfNeeded(reason: "gateway started")
                self.refreshLog()
                return
            } catch {
                self.logger.warning("Gateway health check attempt \(attemptCount) failed: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }

        self.logger.error("Gateway startup timeout after \(attemptCount) attempts")
        self.status = .failed("Gateway did not start in time")
        self.lastFailureReason = "launchd start timeout"
    }

    private func appendLog(_ chunk: String) {
        self.log.append(chunk)
        if self.log.count > self.logLimit {
            self.log = String(self.log.suffix(self.logLimit))
        }
    }

    private func refreshControlChannelIfNeeded(reason: String) {
        switch ControlChannel.shared.state {
        case .connected, .connecting:
            return
        case .disconnected, .degraded:
            break
        }
        self.appendLog("[gateway] refreshing control channel (\(reason))\n")
        self.logger.debug("gateway control channel refresh reason=\(reason)")
        Task { await ControlChannel.shared.configure() }
    }

    func waitForGatewayReady(timeout: TimeInterval = 6) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !self.desiredActive { return false }
            do {
                _ = try await self.connection.requestRaw(method: .health, timeoutMs: 1500)
                self.clearLastFailure()
                return true
            } catch {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        self.appendLog("[gateway] readiness wait timed out\n")
        self.logger.warning("gateway readiness wait timed out")
        return false
    }

    func clearLog() {
        self.log = ""
        try? FileManager().removeItem(atPath: GatewayLaunchAgentManager.launchdGatewayLogPath())
        self.logger.debug("gateway log cleared")
    }

    func setProjectRoot(path: String) {
        CommandResolver.setProjectRoot(path)
    }

    func projectRootPath() -> String {
        CommandResolver.projectRootPath()
    }

    private nonisolated static func readGatewayLog(path: String, limit: Int) -> String {
        guard FileManager().fileExists(atPath: path) else { return "" }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "" }
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.count <= limit { return text }
        return String(text.suffix(limit))
    }
}

#if DEBUG
extension GatewayProcessManager {
    func setTestingConnection(_ connection: GatewayConnection?) {
        self.testingConnection = connection
    }

    func setTestingDesiredActive(_ active: Bool) {
        self.desiredActive = active
    }

    func setTestingLastFailureReason(_ reason: String?) {
        self.lastFailureReason = reason
    }
}
#endif
