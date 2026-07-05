import AppKit
import Darwin
import Foundation

struct MenuConfig {
    var command = "hotspot-proxy-toggle"
    var refreshSeconds = 30.0
    var title = "MHP"
    var locale = MenuLocale.auto

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
            case "--locale":
                index += 1
                guard index < arguments.count, let locale = MenuLocale(rawValue: arguments[index]) else {
                    throw UsageError("invalid value for --locale")
                }
                config.locale = locale
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

enum MenuLocale: String {
    case auto
    case en
    case ko

    var resolved: MenuLocale {
        switch self {
        case .en, .ko:
            return self
        case .auto:
            let defaults = UserDefaults.standard
            let languages = defaults.array(forKey: "AppleLanguages") as? [String] ?? []
            if languages.contains(where: { $0.lowercased().hasPrefix("ko") }) {
                return .ko
            }
            if let locale = defaults.string(forKey: "AppleLocale"), locale.lowercased().hasPrefix("ko") {
                return .ko
            }
            return .en
        }
    }
}

enum ProxySummary {
    case checking
    case on
    case unavailable
    case idle
    case notWiFi
    case error

    func title(locale: MenuLocale) -> String {
        switch locale.resolved {
        case .ko:
            switch self {
            case .checking: return "확인 중"
            case .on: return "✅ 핫스팟 프록시 켜짐"
            case .unavailable: return "⚠️ 핫스팟 프록시 사용 불가"
            case .idle: return "ℹ️ 핫스팟 프록시 대기"
            case .notWiFi: return "Wi-Fi 준비 안 됨"
            case .error: return "MHP 오류"
            }
        case .auto, .en:
            switch self {
            case .checking: return "Checking"
            case .on: return "✅ Hotspot Proxy On"
            case .unavailable: return "⚠️ Hotspot Proxy Unavailable"
            case .idle: return "ℹ️ Hotspot Proxy Idle"
            case .notWiFi: return "Wi-Fi Not Ready"
            case .error: return "MHP Error"
            }
        }
    }

    func statusText(locale: MenuLocale) -> String {
        switch locale.resolved {
        case .ko:
            return "상태: \(title(locale: locale))"
        case .auto, .en:
            return "Status: \(title(locale: locale))"
        }
    }

    func tooltip(locale: MenuLocale) -> String {
        switch locale.resolved {
        case .ko:
            switch self {
            case .checking: return "핫스팟 프록시 상태를 확인하는 중입니다."
            case .on: return "현재 트래픽이 핫스팟 프록시를 사용합니다."
            case .unavailable: return "핫스팟은 감지됐지만 프록시 서버가 응답하지 않습니다."
            case .idle: return "현재 Wi-Fi는 설정한 핫스팟이 아닙니다."
            case .notWiFi: return "Wi-Fi route 또는 router가 준비되지 않았습니다."
            case .error: return "핫스팟 프록시 상태를 읽을 수 없습니다."
            }
        case .auto, .en:
            switch self {
            case .checking: return "Hotspot proxy status is being checked."
            case .on: return "Traffic is using the hotspot proxy."
            case .unavailable: return "Hotspot detected, but the proxy server is not responding."
            case .idle: return "Current Wi-Fi is not a configured hotspot."
            case .notWiFi: return "Wi-Fi route or router is not ready."
            case .error: return "Could not read hotspot proxy status."
            }
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
    private lazy var statusMenuItem = NSMenuItem(
        title: ProxySummary.checking.statusText(locale: config.locale),
        action: nil,
        keyEquivalent: ""
    )
    private var timer: Timer?
    private var isRefreshing = false

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
            button.toolTip = ProxySummary.checking.tooltip(locale: config.locale)
        }

        statusMenuItem.isEnabled = false

        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: menuText(en: "Refresh Status", ko: "상태 새로고침"), action: #selector(refreshStatusFromMenu), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: menuText(en: "Reconcile Now", ko: "지금 동기화"), action: #selector(reconcileNow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: menuText(en: "Quit MHP", ko: "MHP 종료"), action: #selector(quit), keyEquivalent: "q"))

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
                self.apply(summary: summary)
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
        setChecking()
        runCommand(argument: "off") { [weak self] _ in
            self?.bootoutLaunchAgent(label: "com.github.plaonn.hotspot-proxy-toggle.helper") {
                self?.bootoutLaunchAgent(label: "com.github.plaonn.hotspot-proxy-toggle.menu") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func setChecking() {
        statusMenuItem.title = ProxySummary.checking.statusText(locale: config.locale)
        statusItem.button?.toolTip = ProxySummary.checking.tooltip(locale: config.locale)
    }

    private func apply(summary: ProxySummary) {
        statusMenuItem.title = summary.statusText(locale: config.locale)
        statusItem.button?.title = config.title
        statusItem.button?.toolTip = summary.tooltip(locale: config.locale)
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
            return .on
        }

        if firstLine.hasPrefix("status=not-hotspot") {
            return .idle
        }

        if firstLine.hasPrefix("status=not-wifi") || firstLine.hasPrefix("status=no-router") {
            return .notWiFi
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

    private func bootoutLaunchAgent(label: String, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // LaunchAgent may already be unloaded. Quit should still proceed.
            }

            completion()
        }
    }

    private func menuText(en: String, ko: String) -> String {
        switch config.locale.resolved {
        case .ko:
            return ko
        case .auto, .en:
            return en
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
          --locale auto|en|ko
                           Menu language. Default: auto.
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
