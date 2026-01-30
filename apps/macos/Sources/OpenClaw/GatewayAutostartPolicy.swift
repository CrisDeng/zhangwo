import Foundation
import Logging

enum GatewayAutostartPolicy {
    private static let logger = Logger(subsystem: "ai.openclaw", category: "gateway.autostart")
    
    static func shouldStartGateway(mode: AppState.ConnectionMode, paused: Bool) -> Bool {
        let shouldStart = mode == .local && !paused
        self.logger.info("Gateway autostart decision: mode=\(mode), paused=\(paused) -> shouldStart=\(shouldStart)")
        return shouldStart
    }

    static func shouldEnsureLaunchAgent(
        mode: AppState.ConnectionMode,
        paused: Bool) -> Bool
    {
        let shouldEnsure = self.shouldStartGateway(mode: mode, paused: paused)
        self.logger.info("LaunchAgent ensure decision: mode=\(mode), paused=\(paused) -> shouldEnsure=\(shouldEnsure)")
        return shouldEnsure
    }
}
