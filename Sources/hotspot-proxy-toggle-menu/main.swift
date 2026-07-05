import AppKit
import Darwin
import Foundation

struct MenuConfig {
    var command = defaultCommandPath()
    var configPath = defaultConfigPath()
    var statePath = defaultStatePath()
    var refreshSeconds = 30.0
    var title = ""
    var locale = MenuLocale.auto

    static func parse(_ arguments: [String]) throws -> MenuConfig {
        var config = MenuConfig()
        var index = 1

        while index < arguments.count {
            let arg = arguments[index]
            if arg.hasPrefix("--title=") {
                config.title = String(arg.dropFirst("--title=".count))
                index += 1
                continue
            }

            switch arg {
            case "--command":
                index += 1
                guard index < arguments.count else {
                    throw UsageError("missing value for --command")
                }
                config.command = arguments[index]
            case "--config":
                index += 1
                guard index < arguments.count else {
                    throw UsageError("missing value for --config")
                }
                config.configPath = arguments[index]
            case "--refresh":
                index += 1
                guard index < arguments.count, let value = Double(arguments[index]), value > 0 else {
                    throw UsageError("invalid value for --refresh")
                }
                config.refreshSeconds = value
            case "--state":
                index += 1
                guard index < arguments.count else {
                    throw UsageError("missing value for --state")
                }
                config.statePath = arguments[index]
            case "--title":
                index += 1
                guard index < arguments.count else {
                    throw UsageError("missing value for --title")
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

struct NotificationConfig {
    var title = ""
    var body = ""

    static func parse(_ arguments: [String]) throws -> NotificationConfig {
        var config = NotificationConfig()
        var index = 2

        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--title":
                index += 1
                guard index < arguments.count else {
                    throw UsageError("missing value for --title")
                }
                config.title = arguments[index]
            case "--body":
                index += 1
                guard index < arguments.count else {
                    throw UsageError("missing value for --body")
                }
                config.body = arguments[index]
            default:
                throw UsageError("unknown notification argument: \(arg)")
            }

            index += 1
        }

        guard !config.title.isEmpty || !config.body.isEmpty else {
            throw UsageError("notification title or body is required")
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
    case off
    case notWiFi
    case error

    func title(locale: MenuLocale) -> String {
        switch locale.resolved {
        case .ko:
            switch self {
            case .checking: return "확인 중"
            case .on: return "핫스팟 프록시 켜짐"
            case .unavailable: return "핫스팟 프록시 사용 불가"
            case .idle: return "핫스팟 대기"
            case .off: return "MHP 꺼짐"
            case .notWiFi: return "Wi-Fi 준비 안 됨"
            case .error: return "MHP 오류"
            }
        case .auto, .en:
            switch self {
            case .checking: return "Checking"
            case .on: return "Hotspot Proxy On"
            case .unavailable: return "Hotspot Proxy Unavailable"
            case .idle: return "Hotspot Proxy Idle"
            case .off: return "MHP Off"
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
            case .off: return "MHP가 꺼져 있습니다."
            case .notWiFi: return "Wi-Fi route 또는 router가 준비되지 않았습니다."
            case .error: return "핫스팟 프록시 상태를 읽을 수 없습니다."
            }
        case .auto, .en:
            switch self {
            case .checking: return "Hotspot proxy status is being checked."
            case .on: return "Traffic is using the hotspot proxy."
            case .unavailable: return "Hotspot detected, but the proxy server is not responding."
            case .idle: return "Current Wi-Fi is not a configured hotspot."
            case .off: return "MHP is off."
            case .notWiFi: return "Wi-Fi route or router is not ready."
            case .error: return "Could not read hotspot proxy status."
            }
        }
    }

    var iconStyle: MenuBarIcon.Style {
        switch self {
        case .on:
            return .hotspotProxyOn
        case .unavailable, .error:
            return .hotspotProxyOff
        case .checking, .idle, .off, .notWiFi:
            return .nonHotspot
        }
    }
}

enum MenuBarIcon {
    enum Style {
        case hotspotProxyOn
        case nonHotspot
        case hotspotProxyOff
    }

    static func image(for style: Style) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.black.set()

            switch style {
            case .hotspotProxyOn:
                fillPhone(in: rect)
                clearHotspotMark(in: rect)
            case .nonHotspot:
                strokePhone(in: rect)
                drawHotspotMark(in: rect)
            case .hotspotProxyOff:
                fillPhone(in: rect)
                clearHotspotMark(in: rect)
                clearProxyOffSlash(in: rect)
            }

            return true
        }

        image.isTemplate = true
        image.size = size
        return image
    }

    private static func fillPhone(in rect: NSRect) {
        let phone = phoneRect(in: rect)
        NSBezierPath(roundedRect: phone, xRadius: scaledX(2.35, in: rect), yRadius: scaledY(2.35, in: rect)).fill()
    }

    private static func strokePhone(in rect: NSRect) {
        let phone = phoneRect(in: rect).insetBy(dx: scaledX(0.825, in: rect), dy: scaledY(0.825, in: rect))
        let path = NSBezierPath(
            roundedRect: phone,
            xRadius: scaledX(1.55, in: rect),
            yRadius: scaledY(1.55, in: rect)
        )
        path.lineWidth = scaledStroke(1.65, in: rect)
        path.stroke()
    }

    private static func drawHotspotMark(in rect: NSRect) {
        NSColor.black.set()
        hotspotDot(in: rect).fill()
        hotspotArc(in: rect, radius: 2.8).stroke()
        hotspotArc(in: rect, radius: 5.6).stroke()
    }

    private static func clearHotspotMark(in rect: NSRect) {
        withClearBlend {
            hotspotDot(in: rect).fill()
            hotspotArc(in: rect, radius: 2.8).stroke()
            hotspotArc(in: rect, radius: 5.6).stroke()
        }
    }

    private static func clearProxyOffSlash(in rect: NSRect) {
        withClearBlend {
            let path = NSBezierPath()
            path.move(to: point(x: 3.0, y: 16.75, in: rect))
            path.line(to: point(x: 16.15, y: 1.55, in: rect))
            path.lineWidth = scaledStroke(2.15, in: rect)
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    private static func hotspotDot(in rect: NSRect) -> NSBezierPath {
        let center = point(x: 6.85, y: 11.55, in: rect)
        let radius = min(scaledX(1.0, in: rect), scaledY(1.0, in: rect))
        return NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private static func hotspotArc(in rect: NSRect, radius: CGFloat) -> NSBezierPath {
        let center = point(x: 6.85, y: 11.55, in: rect)
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: min(scaledX(radius, in: rect), scaledY(radius, in: rect)),
            startAngle: -90,
            endAngle: 0,
            clockwise: false
        )
        path.lineWidth = scaledStroke(1.55, in: rect)
        path.lineCapStyle = .round
        return path
    }

    private static func phoneRect(in rect: NSRect) -> NSRect {
        NSRect(
            x: rect.minX + scaledX(3.8, in: rect),
            y: rect.minY + scaledY(2.15, in: rect),
            width: scaledX(11.8, in: rect),
            height: scaledY(13.7, in: rect)
        )
    }

    private static func point(x: CGFloat, y: CGFloat, in rect: NSRect) -> NSPoint {
        NSPoint(x: rect.minX + scaledX(x, in: rect), y: rect.minY + scaledY(y, in: rect))
    }

    private static func scaledX(_ value: CGFloat, in rect: NSRect) -> CGFloat {
        value * rect.width / 18
    }

    private static func scaledY(_ value: CGFloat, in rect: NSRect) -> CGFloat {
        value * rect.height / 18
    }

    private static func scaledStroke(_ value: CGFloat, in rect: NSRect) -> CGFloat {
        value * min(rect.width, rect.height) / 18
    }

    private static func withClearBlend(_ draw: () -> Void) {
        guard let context = NSGraphicsContext.current else {
            return
        }

        let previousOperation = context.compositingOperation
        context.compositingOperation = .clear
        draw()
        context.compositingOperation = previousOperation
    }
}

struct CommandResult {
    let status: Int32
    let output: String
}

struct UIState: Decodable {
    let version: Int
    let kind: String
    let proxyType: String
    let detail: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case version
        case kind
        case proxyType = "proxy_type"
        case detail
        case updatedAt = "updated_at"
    }
}

struct AppSettings {
    var hotspotSSID = ""
    var proxyType = "socks5"
    var proxyPort = "1080"
    var language = "auto"
    var proxyCheckTimeout = "3"
    var helperWatchdogSeconds = "60"
}

final class DotenvConfig {
    private var lines: [String]
    private var values: [String: String]

    private init(lines: [String], values: [String: String]) {
        self.lines = lines
        self.values = values
    }

    static func load(path: String) -> DotenvConfig {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let lines = text.isEmpty ? [] : text.components(separatedBy: .newlines)
        var values: [String: String] = [:]

        for line in lines {
            guard let (key, value) = parse(line: line) else {
                continue
            }
            values[key] = value
        }

        return DotenvConfig(lines: lines, values: values)
    }

    func appSettings() -> AppSettings {
        AppSettings(
            hotspotSSID: values["HOTSPOT_SSID"] ?? "",
            proxyType: values["PROXY_TYPE"] ?? "socks5",
            proxyPort: values["PROXY_PORT"] ?? "1080",
            language: values["LANGUAGE"] ?? values["NOTIFICATION_LOCALE"] ?? "auto",
            proxyCheckTimeout: values["PROXY_CHECK_TIMEOUT"] ?? "3",
            helperWatchdogSeconds: values["HELPER_WATCHDOG_SECONDS"] ?? "60"
        )
    }

    func set(_ key: String, _ value: String) {
        values[key] = value
    }

    func write(path: String) throws {
        let writeKeys = [
            "HOTSPOT_SSID",
            "PROXY_TYPE",
            "PROXY_PORT",
            "LANGUAGE",
            "REQUIRE_PROXY_CHECK",
            "PROXY_CHECK_TIMEOUT",
            "HELPER_WATCHDOG_SECONDS",
        ]
        var seen = Set<String>()
        var output: [String] = []

        for line in lines {
            if let (key, _) = DotenvConfig.parse(line: line), writeKeys.contains(key) {
                output.append("\(key)=\(DotenvConfig.quote(values[key] ?? ""))")
                seen.insert(key)
            } else if let (key, _) = DotenvConfig.parse(line: line), legacyKeysToDrop.contains(key) {
                continue
            } else if !line.isEmpty {
                output.append(line)
            }
        }

        for key in writeKeys where !seen.contains(key) {
            if let value = values[key] {
                output.append("\(key)=\(DotenvConfig.quote(value))")
            }
        }

        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try (output.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func parse(line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else {
            return nil
        }

        let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
        guard key.range(of: #"^[A-Z_][A-Z0-9_]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        let rawValue = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        return (key, unquote(rawValue))
    }

    private static func unquote(_ raw: String) -> String {
        if raw.count >= 2, raw.hasPrefix("'"), raw.hasSuffix("'") {
            return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
        }
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
            return String(raw.dropFirst().dropLast())
        }
        return raw.replacingOccurrences(of: "\\ ", with: " ")
    }

    private static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private var legacyKeysToDrop: Set<String> {
        [
            "HOTSPOT_SSIDS",
            "HOTSPOT_DHCP_MARKERS",
            "STRICT_SSID",
            "NOTIFICATION_LOCALE",
        ]
    }
}

final class AutomationController {
    private let command: String
    private let helperWatchdogSeconds: String

    init(command: String, helperWatchdogSeconds: String) {
        self.command = command
        self.helperWatchdogSeconds = helperWatchdogSeconds
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: helperPlistPath)
            && FileManager.default.fileExists(atPath: menuPlistPath)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            let helperChanged = try writeLaunchAgents()
            if helperChanged || !launchAgentIsLoaded(label: helperLabel) {
                _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(helperLabel)"])
                _ = runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", helperPlistPath])
                _ = runLaunchctl(arguments: ["kickstart", "-k", "gui/\(getuid())/\(helperLabel)"])
            }
            if !launchAgentIsLoaded(label: menuLabel) {
                _ = runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", menuPlistPath])
                _ = runLaunchctl(arguments: ["kickstart", "-k", "gui/\(getuid())/\(menuLabel)"])
            }
        } else {
            _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(helperLabel)"])
            try? FileManager.default.removeItem(atPath: helperPlistPath)
            try? FileManager.default.removeItem(atPath: menuPlistPath)
        }
    }

    private func writeLaunchAgents() throws -> Bool {
        guard FileManager.default.isExecutableFile(atPath: helperBinaryPath) else {
            throw UsageError("helper binary not found: \(helperBinaryPath)")
        }
        guard FileManager.default.isExecutableFile(atPath: command) else {
            throw UsageError("command not found: \(command)")
        }
        guard let menuBinaryPath = Bundle.main.executablePath,
              FileManager.default.isExecutableFile(atPath: menuBinaryPath) else {
            throw UsageError("menu binary not found")
        }

        try FileManager.default.createDirectory(
            atPath: launchAgentsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            atPath: logDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let helperChanged = try writeIfChanged(
            helperPlist(helper: helperBinaryPath, command: command),
            path: helperPlistPath
        )
        _ = try writeIfChanged(
            menuPlist(menu: menuBinaryPath, command: command),
            path: menuPlistPath
        )
        return helperChanged
    }

    private func writeIfChanged(_ content: String, path: String) throws -> Bool {
        if let existing = try? String(contentsOfFile: path, encoding: .utf8),
           existing == content {
            return false
        }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return true
    }

    private func helperPlist(helper: String, command: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(helperLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(xmlEscape(helper))</string>
            <string>--command</string>
            <string>\(xmlEscape(command))</string>
            <string>--debounce</string>
            <string>1</string>
            <string>--max-runs</string>
            <string>3</string>
            <string>--window</string>
            <string>10</string>
            <string>--watchdog</string>
            <string>\(xmlEscape(helperWatchdogSeconds))</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(xmlEscape(logDirectory))/hotspot-proxy-toggle-helper.stdout.log</string>
          <key>StandardErrorPath</key>
          <string>\(xmlEscape(logDirectory))/hotspot-proxy-toggle-helper.stderr.log</string>
        </dict>
        </plist>
        """
    }

    private func menuPlist(menu: String, command: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(menuLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(xmlEscape(menu))</string>
            <string>--command</string>
            <string>\(xmlEscape(command))</string>
            <string>--config</string>
            <string>\(xmlEscape(defaultConfigPath()))</string>
            <string>--state</string>
            <string>\(xmlEscape(defaultStatePath()))</string>
            <string>--refresh</string>
            <string>30</string>
            <string>--locale</string>
            <string>auto</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(xmlEscape(logDirectory))/hotspot-proxy-toggle-menu.stdout.log</string>
          <key>StandardErrorPath</key>
          <string>\(xmlEscape(logDirectory))/hotspot-proxy-toggle-menu.stderr.log</string>
        </dict>
        </plist>
        """
    }

    private var launchAgentsDirectory: String {
        "\(homeDirectory())/Library/LaunchAgents"
    }

    private var logDirectory: String {
        "\(homeDirectory())/Library/Logs"
    }

    private var helperBinaryPath: String {
        "\(homeDirectory())/.local/share/hotspot-proxy-toggle/bin/hotspot-proxy-toggle-helper"
    }

    private var helperPlistPath: String {
        "\(launchAgentsDirectory)/\(helperLabel).plist"
    }

    private var menuPlistPath: String {
        "\(launchAgentsDirectory)/\(menuLabel).plist"
    }

    private var helperLabel: String {
        "com.github.plaonn.hotspot-proxy-toggle.helper"
    }

    private var menuLabel: String {
        "com.github.plaonn.hotspot-proxy-toggle.menu"
    }

    private func launchAgentIsLoaded(label: String) -> Bool {
        runLaunchctl(arguments: ["print", "gui/\(getuid())/\(label)"]) == 0
    }

    private func runLaunchctl(arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in
                finished.signal()
            }
            try process.run()
            if finished.wait(timeout: .now() + 10) == .timedOut {
                process.terminate()
                return 124
            }
            return process.terminationStatus
        } catch {
            return 127
        }
    }
}

final class SettingsWindowController: NSWindowController {
    private let config: MenuConfig
    private let hotspotLabel = NSTextField(labelWithString: "")
    private let proxyTypeLabel = NSTextField(labelWithString: "")
    private let proxyPortLabel = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let advancedLabel = NSTextField(labelWithString: "")
    private let timeoutLabel = NSTextField(labelWithString: "")
    private let watchdogLabel = NSTextField(labelWithString: "")
    private let hotspotField = NSTextField()
    private let proxyTypePopup = NSPopUpButton()
    private let proxyPortField = NSTextField()
    private let languagePopup = NSPopUpButton()
    private let startAutomaticallyCheckbox = NSButton(checkboxWithTitle: "Start Automatically", target: nil, action: nil)
    private let timeoutField = NSTextField()
    private let watchdogField = NSTextField()
    private let openConfigButton = NSButton()
    private let openLogButton = NSButton()
    private let saveButton = NSButton()

    init(config: MenuConfig) {
        self.config = config

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        super.init(window: window)
        buildContent()
        loadValues()
        applyLanguage()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        proxyTypePopup.addItems(withTitles: ["SOCKS5", "HTTP/HTTPS Web Proxy"])
        languagePopup.addItems(withTitles: ["System Default", "English", "한국어"])
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)

        stack.addArrangedSubview(row(labelView: hotspotLabel, control: hotspotField))
        stack.addArrangedSubview(row(labelView: proxyTypeLabel, control: proxyTypePopup))
        stack.addArrangedSubview(row(labelView: proxyPortLabel, control: proxyPortField))
        stack.addArrangedSubview(row(labelView: languageLabel, control: languagePopup))
        stack.addArrangedSubview(startAutomaticallyCheckbox)
        configureSeparator(advancedLabel)
        stack.addArrangedSubview(advancedLabel)
        stack.addArrangedSubview(row(labelView: timeoutLabel, control: timeoutField, labelWidth: 250, controlWidth: 80))
        stack.addArrangedSubview(row(labelView: watchdogLabel, control: watchdogField, labelWidth: 250, controlWidth: 80))

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY
        buttons.distribution = .fillEqually

        openConfigButton.target = self
        openConfigButton.action = #selector(openConfig)
        openLogButton.target = self
        openLogButton.action = #selector(openLog)
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        buttons.addArrangedSubview(openConfigButton)
        buttons.addArrangedSubview(openLogButton)
        buttons.addArrangedSubview(saveButton)
        stack.addArrangedSubview(buttons)
    }

    private func row(labelView: NSTextField, control: NSView, labelWidth: CGFloat = 150, controlWidth: CGFloat = 190) -> NSStackView {
        labelView.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        control.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
        return row
    }

    private func configureSeparator(_ view: NSTextField) {
        view.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        view.textColor = .secondaryLabelColor
    }

    private func loadValues() {
        let settings = DotenvConfig.load(path: config.configPath).appSettings()
        hotspotField.stringValue = settings.hotspotSSID
        proxyTypePopup.selectItem(at: settings.proxyType == "http" ? 1 : 0)
        proxyPortField.stringValue = settings.proxyPort
        languagePopup.selectItem(at: ["auto", "en", "ko"].firstIndex(of: settings.language) ?? 0)
        timeoutField.stringValue = settings.proxyCheckTimeout
        watchdogField.stringValue = settings.helperWatchdogSeconds
        startAutomaticallyCheckbox.state = AutomationController(
            command: config.command,
            helperWatchdogSeconds: settings.helperWatchdogSeconds
        ).isEnabled ? .on : .off
    }

    @objc private func languageChanged() {
        applyLanguage()
    }

    private func applyLanguage() {
        let korean = selectedLanguage().resolved == .ko
        window?.title = korean ? "MHP 설정" : "MHP Settings"
        hotspotLabel.stringValue = korean ? "핫스팟 SSID" : "Hotspot SSID"
        proxyTypeLabel.stringValue = korean ? "프록시 유형" : "Proxy Type"
        proxyPortLabel.stringValue = korean ? "프록시 포트" : "Proxy Port"
        languageLabel.stringValue = korean ? "언어" : "Language"
        startAutomaticallyCheckbox.title = korean ? "자동 시작" : "Start Automatically"
        advancedLabel.stringValue = korean ? "고급" : "Advanced"
        timeoutLabel.stringValue = korean ? "프록시 확인 제한시간 (초)" : "Proxy Check Timeout (seconds)"
        watchdogLabel.stringValue = korean ? "Watchdog 간격 (초)" : "Watchdog Interval (seconds)"
        openConfigButton.title = korean ? "설정 파일 열기" : "Open Config"
        openLogButton.title = korean ? "로그 열기" : "Open Log"
        saveButton.title = korean ? "저장" : "Save"
    }

    private func selectedLanguage() -> MenuLocale {
        let languages = ["auto", "en", "ko"]
        let selected = languages.indices.contains(languagePopup.indexOfSelectedItem)
            ? languages[languagePopup.indexOfSelectedItem]
            : "auto"
        return MenuLocale(rawValue: selected) ?? .auto
    }

    @objc private func save() {
        guard validatePositiveInteger(proxyPortField.stringValue, nameEn: "Proxy Port", nameKo: "프록시 포트", min: 1, max: 65535),
              validatePositiveInteger(timeoutField.stringValue, nameEn: "Proxy Check Timeout", nameKo: "프록시 확인 제한시간", min: 1, max: 60),
              validatePositiveInteger(watchdogField.stringValue, nameEn: "Watchdog Interval", nameKo: "Watchdog 간격", min: 0, max: 3600) else {
            return
        }

        let command = config.command
        let configPath = config.configPath
        let hotspotSSID = hotspotField.stringValue
        let proxyType = proxyTypePopup.indexOfSelectedItem == 1 ? "http" : "socks5"
        let proxyPort = proxyPortField.stringValue
        let language = ["auto", "en", "ko"][languagePopup.indexOfSelectedItem]
        let proxyCheckTimeout = timeoutField.stringValue
        let helperWatchdogSeconds = watchdogField.stringValue
        let startAutomatically = startAutomaticallyCheckbox.state == .on

        setSaving(true)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                let configFile = DotenvConfig.load(path: configPath)
                configFile.set("HOTSPOT_SSID", hotspotSSID)
                configFile.set("PROXY_TYPE", proxyType)
                configFile.set("PROXY_PORT", proxyPort)
                configFile.set("LANGUAGE", language)
                configFile.set("REQUIRE_PROXY_CHECK", "1")
                configFile.set("PROXY_CHECK_TIMEOUT", proxyCheckTimeout)
                configFile.set("HELPER_WATCHDOG_SECONDS", helperWatchdogSeconds)

                try configFile.write(path: configPath)
                try AutomationController(
                    command: command,
                    helperWatchdogSeconds: helperWatchdogSeconds
                ).setEnabled(startAutomatically)
                self?.runCommand(argument: "run")
                DispatchQueue.main.async {
                    self?.close()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.setSaving(false)
                    self?.showError(String(describing: error))
                }
            }
        }
    }

    private func setSaving(_ saving: Bool) {
        saveButton.isEnabled = !saving
        saveButton.title = saving
            ? (selectedLanguage().resolved == .ko ? "저장 중..." : "Saving...")
            : (selectedLanguage().resolved == .ko ? "저장" : "Save")
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(URL(fileURLWithPath: config.configPath))
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(homeDirectory())/Library/Logs/hotspot-proxy-toggle.log"))
    }

    private func validatePositiveInteger(_ rawValue: String, nameEn: String, nameKo: String, min: Int, max: Int) -> Bool {
        guard let value = Int(rawValue), value >= min, value <= max else {
            let korean = selectedLanguage().resolved == .ko
            let name = korean ? nameKo : nameEn
            let message = korean
                ? "\(name)은 \(min)에서 \(max) 사이여야 합니다."
                : "\(name) must be between \(min) and \(max)."
            showError(message)
            return false
        }
        return true
    }

    private func showError(_ message: String) {
        let korean = selectedLanguage().resolved == .ko
        let alert = NSAlert()
        alert.messageText = korean ? "설정을 저장할 수 없음" : "Could not save settings"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func runCommand(argument: String) {
        let process = Process()
        if config.command.contains("/") {
            process.executableURL = URL(fileURLWithPath: config.command)
            process.arguments = [argument]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [config.command, argument]
        }
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }
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
    private var stateWatcher: DispatchSourceFileSystemObject?
    private var stateDirectoryWatcher: DispatchSourceFileSystemObject?
    private var settingsWindowController: SettingsWindowController?

    init(config: MenuConfig) {
        self.config = config
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        ensureAutomationAgentLoaded()
        readStateOrRefresh()
        startStateWatchers()
        timer = Timer.scheduledTimer(withTimeInterval: config.refreshSeconds, repeats: true) { [weak self] _ in
            self?.readStateOrRefresh()
        }
    }

    private func configureStatusItem() {
        statusItem.length = config.title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        if let button = statusItem.button {
            button.title = config.title
            button.image = MenuBarIcon.image(for: ProxySummary.checking.iconStyle)
            button.imagePosition = config.title.isEmpty ? .imageOnly : .imageLeft
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = ProxySummary.checking.tooltip(locale: effectiveLocale())
        }

        statusMenuItem.isEnabled = false

        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: menuText(en: "Settings...", ko: "설정..."), action: #selector(openSettings), keyEquivalent: ","))
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

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(config: config)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        statusMenuItem.title = ProxySummary.checking.statusText(locale: effectiveLocale())
        statusItem.button?.image = MenuBarIcon.image(for: ProxySummary.checking.iconStyle)
        statusItem.button?.toolTip = ProxySummary.checking.tooltip(locale: effectiveLocale())
    }

    private func apply(summary: ProxySummary) {
        let locale = effectiveLocale()
        statusMenuItem.title = summary.statusText(locale: locale)
        statusItem.button?.title = config.title
        statusItem.button?.image = MenuBarIcon.image(for: summary.iconStyle)
        statusItem.button?.imagePosition = config.title.isEmpty ? .imageOnly : .imageLeft
        statusItem.button?.toolTip = summary.tooltip(locale: locale)
    }

    private func readStateOrRefresh() {
        if applyStateFile() {
            return
        }
        refreshStatus()
    }

    @discardableResult
    private func applyStateFile() -> Bool {
        let url = URL(fileURLWithPath: config.statePath)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(UIState.self, from: data) else {
            return false
        }

        DispatchQueue.main.async {
            self.apply(summary: self.summarizeState(state))
        }
        return true
    }

    private func summarizeState(_ state: UIState) -> ProxySummary {
        switch state.kind {
        case "on": return .on
        case "unavailable": return .unavailable
        case "idle": return .idle
        case "off": return .off
        case "not_wifi": return .notWiFi
        default: return .error
        }
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
            _ = self.runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(label)"])
            completion()
        }
    }

    private func startStateWatchers() {
        watchStateDirectory()
        watchStateFile()
    }

    private func watchStateDirectory() {
        let directory = (config.statePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.watchStateFile()
            _ = self?.applyStateFile()
        }
        source.setCancelHandler {
            close(fd)
        }
        stateDirectoryWatcher = source
        source.resume()
    }

    private func watchStateFile() {
        stateWatcher?.cancel()
        stateWatcher = nil

        guard FileManager.default.fileExists(atPath: config.statePath) else {
            return
        }

        let fd = open(config.statePath, O_EVTONLY)
        guard fd >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.watchStateFile()
            _ = self?.applyStateFile()
        }
        source.setCancelHandler {
            close(fd)
        }
        stateWatcher = source
        source.resume()
    }

    private func ensureAutomationAgentLoaded() {
        DispatchQueue.global(qos: .utility).async {
            let candidates = [
                (
                    label: "com.github.plaonn.hotspot-proxy-toggle.helper",
                    plist: "\(homeDirectory())/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.helper.plist"
                ),
                (
                    label: "com.github.plaonn.hotspot-proxy-toggle",
                    plist: "\(homeDirectory())/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.plist"
                ),
            ]

            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.plist) {
                if self.launchAgentIsLoaded(label: candidate.label) {
                    return
                }

                _ = self.runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", candidate.plist])
                _ = self.runLaunchctl(arguments: ["kickstart", "-k", "gui/\(getuid())/\(candidate.label)"])
                return
            }
        }
    }

    private func launchAgentIsLoaded(label: String) -> Bool {
        runLaunchctl(arguments: ["print", "gui/\(getuid())/\(label)"]) == 0
    }

    private func runLaunchctl(arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 127
        }
    }

    private func menuText(en: String, ko: String) -> String {
        switch effectiveLocale().resolved {
        case .ko:
            return ko
        case .auto, .en:
            return en
        }
    }

    private func effectiveLocale() -> MenuLocale {
        if config.locale != .auto {
            return config.locale
        }

        let language = DotenvConfig.load(path: config.configPath).appSettings().language
        return MenuLocale(rawValue: language) ?? .auto
    }
}

func defaultCommandPath() -> String {
    let installedPath = "\(homeDirectory())/.local/share/hotspot-proxy-toggle/bin/hotspot-proxy-toggle"
    if FileManager.default.isExecutableFile(atPath: installedPath) {
        return installedPath
    }
    return "hotspot-proxy-toggle"
}

func defaultConfigPath() -> String {
    "\(homeDirectory())/.config/hotspot-proxy-toggle.conf"
}

func defaultStatePath() -> String {
    "\(homeDirectory())/Library/Application Support/hotspot-proxy-toggle/status.json"
}

func defaultLockPath() -> String {
    "\(homeDirectory())/Library/Application Support/hotspot-proxy-toggle/menu.lock"
}

func acquireSingleInstanceLock() -> Int32? {
    let lockPath = defaultLockPath()
    let directory = (lockPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(
        atPath: directory,
        withIntermediateDirectories: true,
        attributes: nil
    )

    let fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fd >= 0 else {
        return nil
    }

    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        close(fd)
        return nil
    }

    return fd
}

func homeDirectory() -> String {
    FileManager.default.homeDirectoryForCurrentUser.path
}

func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func printUsage() {
    print(
        """
        Usage:
          hotspot-proxy-toggle-menu [options]

        Options:
          --command PATH     Command to invoke with 'status' or 'run'.
          --config PATH      Config file path.
          --refresh SECS    Status refresh interval. Default: 30.
          --state PATH      UI state JSON path.
          --title TEXT      Menu bar title. Default: icon only.
          --locale auto|en|ko
                           Menu language. Default: auto.
          -h, --help        Show this help.
        """
    )
}

do {
    if CommandLine.arguments.dropFirst().first == "--notify" {
        let config = try NotificationConfig.parse(CommandLine.arguments)
        sendBundledNotification(title: config.title, body: config.body)
    } else {
        guard let instanceLockFD = acquireSingleInstanceLock() else {
            exit(0)
        }

        let config = try MenuConfig.parse(CommandLine.arguments)
        let app = NSApplication.shared
        let delegate = MenuBarApp(config: config)
        app.delegate = delegate
        _ = instanceLockFD
        app.run()
    }
} catch let error as UsageError {
    fputs("error: \(error.description)\n", stderr)
    printUsage()
    exit(64)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}

func sendBundledNotification(title: String, body: String) {
    let notification = NSUserNotification()
    notification.title = title
    notification.informativeText = body
    NSUserNotificationCenter.default.deliver(notification)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
}
