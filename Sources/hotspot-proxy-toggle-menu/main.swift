import AppKit
import Foundation

struct MenuConfig {
    var command = "hotspot-proxy-toggle"
    var refreshSeconds = 30.0
    var title = "MHP"

    static func parse(_ arguments: [String]) throws -> MenuConfig {
        var config = MenuConfig()
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
            case "--refresh":
                index += 1
                guard index < arguments.count, let value = Double(arguments[index]), value > 0 else {
                    throw UsageError("invalid value for --refresh")
                }
                config.refreshSeconds = value
            case "--title":
                index += 1
                guard index < arguments.count, !arguments[index].isEmpty else {
                    throw UsageError("invalid value for --title")
                }
                config.title = arguments[index]
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

enum ProxySummary {
    case checking
    case active
    case unavailable
    case idle
    case transient
    case error

    var statusText: String {
        switch self {
        case .checking: return "Status: Checking..."
        case .active: return "Status: Active"
        case .unavailable: return "Status: Proxy unavailable"
        case .idle: return "Status: Idle"
        case .transient: return "Status: Waiting for Wi-Fi"
        case .error: return "Status: Error"
        }
    }

    var tooltip: String {
        switch self {
        case .checking: return "Hotspot proxy status is being checked."
        case .active: return "Hotspot proxy is active or ready."
        case .unavailable: return "Hotspot detected, but the proxy endpoint is unavailable."
        case .idle: return "Current Wi-Fi is not a configured hotspot."
        case .transient: return "Wi-Fi route or router is not ready."
        case .error: return "Could not read hotspot proxy status."
        }
    }
}

struct CommandResult {
    let status: Int32
    let output: String
}

final class MenuBarApp: NSObject, NSApplicationDelegate {
    private let config: MenuConfig
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: ProxySummary.checking.statusText, action: nil, keyEquivalent: "")
    private let lastCheckedMenuItem = NSMenuItem(title: "Last checked: Never", action: nil, keyEquivalent: "")
    private var timer: Timer?
    private var isRefreshing = false
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    init(config: MenuConfig) {
        self.config = config
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refreshStatus()
        timer = Timer.scheduledTimer(withTimeInterval: config.refreshSeconds, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.title = config.title
            button.toolTip = ProxySummary.checking.tooltip
        }

        statusMenuItem.isEnabled = false
        lastCheckedMenuItem.isEnabled = false

        menu.addItem(statusMenuItem)
        menu.addItem(lastCheckedMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh Status", action: #selector(refreshStatusFromMenu), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Reconcile Now", action: #selector(reconcileNow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MHP", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    @objc private func refreshStatusFromMenu() {
        refreshStatus()
    }

    private func refreshStatus() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        runCommand(argument: "status") { [weak self] result in
            guard let self else {
                return
            }

            let summary = self.summarizeStatus(result)
            DispatchQueue.main.async {
                self.apply(summary: summary, checkedAt: Date())
                self.isRefreshing = false
            }
        }
    }

    @objc private func reconcileNow() {
        setChecking()
        runCommand(argument: "run") { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRefreshing = false
                self?.refreshStatus()
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setChecking() {
        statusMenuItem.title = ProxySummary.checking.statusText
        statusItem.button?.toolTip = ProxySummary.checking.tooltip
    }

    private func apply(summary: ProxySummary, checkedAt: Date) {
        statusMenuItem.title = summary.statusText
        lastCheckedMenuItem.title = "Last checked: \(timeFormatter.string(from: checkedAt))"
        statusItem.button?.title = config.title
        statusItem.button?.toolTip = summary.tooltip
    }

    private func summarizeStatus(_ result: CommandResult) -> ProxySummary {
        guard result.status == 0 || result.status == 1 || result.status == 2 else {
            return .error
        }

        let lines = result.output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let firstLine = lines.first else {
            return .error
        }

        if firstLine.hasPrefix("status=hotspot") {
            if lines.contains(where: { $0.contains("proxy_check=") && $0.contains("-missing") }) {
                return .unavailable
            }
            return .active
        }

        if firstLine.hasPrefix("status=not-hotspot") {
            return .idle
        }

        if firstLine.hasPrefix("status=not-wifi") || firstLine.hasPrefix("status=no-router") {
            return .transient
        }

        return .error
    }

    private func runCommand(argument: String, completion: @escaping (CommandResult) -> Void) {
        let command = config.command
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            if command.contains("/") {
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = [argument]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [command, argument]
            }

            let output = Pipe()
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                completion(CommandResult(status: 127, output: String(describing: error)))
                return
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            completion(CommandResult(status: process.terminationStatus, output: text))
        }
    }
}

func printUsage() {
    print(
        """
        Usage:
          hotspot-proxy-toggle-menu [options]

        Options:
          --command PATH     Command to invoke with 'status' or 'run'.
          --refresh SECS    Status refresh interval. Default: 30.
          --title TEXT      Menu bar title. Default: MHP.
          -h, --help        Show this help.
        """
    )
}

do {
    let config = try MenuConfig.parse(CommandLine.arguments)
    let app = NSApplication.shared
    let delegate = MenuBarApp(config: config)
    app.delegate = delegate
    app.run()
} catch let error as UsageError {
    fputs("error: \(error.description)\n", stderr)
    printUsage()
    exit(64)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
