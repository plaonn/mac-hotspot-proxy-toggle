import Dispatch
import Foundation
import SystemConfiguration

struct HelperConfig {
    var command = "hotspot-proxy-toggle"
    var debounceSeconds = 1.0
    var maxRuns = 3
    var windowSeconds = 10.0
    var dryRun = false
    var once = false

    static func parse(_ arguments: [String]) throws -> HelperConfig {
        var config = HelperConfig()
        var index = 1

        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--command":
                index += 1
                guard index < arguments.count else {
                    throw UsageError("missing value for --command")
                }
                config.command = arguments[index]
            case "--debounce":
                index += 1
                guard index < arguments.count, let value = Double(arguments[index]), value >= 0 else {
                    throw UsageError("invalid value for --debounce")
                }
                config.debounceSeconds = value
            case "--max-runs":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]), value > 0 else {
                    throw UsageError("invalid value for --max-runs")
                }
                config.maxRuns = value
            case "--window":
                index += 1
                guard index < arguments.count, let value = Double(arguments[index]), value > 0 else {
                    throw UsageError("invalid value for --window")
                }
                config.windowSeconds = value
            case "--dry-run":
                config.dryRun = true
            case "--once":
                config.once = true
            case "-h", "--help", "help":
                printUsage()
                exit(0)
            default:
                throw UsageError("unknown argument: \(arg)")
            }

            index += 1
        }

        return config
    }
}

struct UsageError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

final class EventHelper {
    private let config: HelperConfig
    private let queue = DispatchQueue(label: "com.github.plaonn.hotspot-proxy-toggle.helper")
    private var store: SCDynamicStore?
    private var isRunScheduled = false
    private var isRunning = false
    private var pendingAfterRun = false
    private var recentRuns: [Date] = []

    init(config: HelperConfig) {
        self.config = config
    }

    func runOnce() -> Int32 {
        return runCommand(reason: "manual-once")
    }

    func start() -> Never {
        var context = SCDynamicStoreContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: SCDynamicStoreCallBack = { _, changedKeys, info in
            guard let info else {
                return
            }

            let helper = Unmanaged<EventHelper>.fromOpaque(info).takeUnretainedValue()
            let keys = (changedKeys as? [String]) ?? []
            helper.handleNetworkChange(keys: keys)
        }

        guard let dynamicStore = SCDynamicStoreCreate(
            nil,
            "hotspot-proxy-toggle-helper" as CFString,
            callback,
            &context
        ) else {
            fatalError("failed to create SCDynamicStore")
        }

        let patterns = [
            "State:/Network/Global/IPv4",
            "State:/Network/Interface/.*/IPv4",
            "State:/Network/Service/.*/IPv4",
            "State:/Network/Service/.*/DNS",
        ] as CFArray

        guard SCDynamicStoreSetNotificationKeys(dynamicStore, nil, patterns) else {
            fatalError("failed to set SCDynamicStore notification keys")
        }

        guard SCDynamicStoreSetDispatchQueue(dynamicStore, queue) else {
            fatalError("failed to schedule SCDynamicStore dispatch queue")
        }

        store = dynamicStore
        log("started helper; command=\(config.command) dry_run=\(config.dryRun)")

        queue.async {
            self.scheduleRun(reason: "startup")
        }

        dispatchMain()
    }

    private func handleNetworkChange(keys: [String]) {
        queue.async {
            let summary = keys.isEmpty ? "unknown keys" : keys.joined(separator: ",")
            self.log("network change: \(summary)")
            self.scheduleRun(reason: "network-change")
        }
    }

    private func scheduleRun(reason: String) {
        if isRunning {
            pendingAfterRun = true
            log("run pending after current run; reason=\(reason)")
            return
        }

        if isRunScheduled {
            log("run already scheduled; reason=\(reason)")
            return
        }

        isRunScheduled = true
        let delay = config.debounceSeconds
        queue.asyncAfter(deadline: .now() + delay) {
            self.isRunScheduled = false
            self.runIfAllowed(reason: reason)
        }
    }

    private func runIfAllowed(reason: String) {
        let now = Date()
        recentRuns = recentRuns.filter { now.timeIntervalSince($0) <= config.windowSeconds }

        if recentRuns.count >= config.maxRuns {
            log("throttled run; reason=\(reason)")
            return
        }

        recentRuns.append(now)
        isRunning = true
        let status = runCommand(reason: reason)
        isRunning = false

        if status != 0 {
            log("command exited with status=\(status)")
        }

        if pendingAfterRun {
            pendingAfterRun = false
            scheduleRun(reason: "pending-event")
        }
    }

    private func runCommand(reason: String) -> Int32 {
        log("running command; reason=\(reason)")

        let process = Process()
        if config.command.contains("/") {
            process.executableURL = URL(fileURLWithPath: config.command)
            process.arguments = ["run"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [config.command, "run"]
        }

        var environment = ProcessInfo.processInfo.environment
        if config.dryRun {
            environment["DRY_RUN"] = "1"
        }
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log("failed to start command: \(error)")
            return 127
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            text.split(separator: "\n", omittingEmptySubsequences: false).forEach { line in
                log("command: \(line)")
            }
        }

        return process.terminationStatus
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("\(timestamp) \(message)")
        fflush(stdout)
    }
}

func printUsage() {
    print(
        """
        Usage:
          hotspot-proxy-toggle-helper [options]

        Options:
          --command PATH     Command to invoke with the 'run' argument.
          --debounce SECS    Debounce window before running. Default: 1.
          --max-runs N       Maximum runs in the throttle window. Default: 3.
          --window SECS      Throttle window. Default: 10.
          --dry-run          Set DRY_RUN=1 for the child command.
          --once             Run the child command once and exit.
          -h, --help         Show this help.
        """
    )
}

do {
    let config = try HelperConfig.parse(CommandLine.arguments)
    let helper = EventHelper(config: config)
    if config.once {
        exit(helper.runOnce())
    }
    helper.start()
} catch let error as UsageError {
    fputs("error: \(error.description)\n", stderr)
    printUsage()
    exit(64)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
