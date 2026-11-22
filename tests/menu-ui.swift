import AppKit
import Foundation

private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

func runMenuUITests() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var config = MenuConfig()
    config.configPath = homeDirectory() + "/test.conf"
    config.command = "/usr/bin/true"
    try "HOTSPOT_SSID='Sample Phone'\nLANGUAGE=ko\n".write(toFile: config.configPath, atomically: true, encoding: .utf8)
    let ui = MenuBarApp(config: config)
    ui.configureStatusItem()
    let menu = ui.menu
    func visibleTitles() -> [String] {
        ui.menuNeedsUpdate(menu)
        return menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
    }
    func perform(_ title: String) {
        let index = menu.indexOfItem(withTitle: title)
        precondition(index >= 0)
        menu.performActionForItem(at: index)
    }
    ui.apply(summary: .on)
    precondition(visibleTitles() == ["핫스팟 프록시 연결됨", "설정…", "종료"])
    ui.apply(summary: .unavailable("timeout"))
    let manual = visibleTitles()
    precondition(manual == ["프록시 응답 대기 중", "응답 시간이 초과됐습니다.", "지금 다시 연결", "설정…", "종료"])
    let identity = defaultWiFiIdentityPath()
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: identity).deletingLastPathComponent(), withIntermediateDirectories: true)
    let fd = RetryActivity.begin(identityPath: identity)
    precondition(fd >= 0)
    precondition(visibleTitles()[1].contains("자동으로 다시 시도"))
    ui.apply(summary: .unavailable("authentication_required"))
    precondition(visibleTitles().prefix(2) == ["프록시 인증 필요", "인증 없는 프록시만 지원합니다."])
    close(fd)
    ui.apply(summary: .unavailable("timeout"))
    precondition(visibleTitles() == manual)
    ui.apply(summary: .needsHotspotName)
    precondition(visibleTitles()[0] == "핫스팟 이름 설정 필요")
    ui.apply(summary: .identityUnknown)
    precondition(visibleTitles()[0] == "현재 Wi-Fi 이름 확인 불가")

    perform("설정…")
    let window = app.windows.first { $0.title.hasSuffix(" 설정") }!
    let content = window.contentView!
    func views<T: NSView>(_ type: T.Type) -> [T] {
        descendants(content).compactMap { $0 as? T }.filter { !$0.isHiddenOrHasHiddenAncestor }
    }
    func button(_ title: String) -> NSButton {
        views(NSButton.self).first { $0.title == title }!
    }
    let name = views(NSTextField.self).first { $0.isEditable && $0.stringValue == "Sample Phone" }!
    let smallHeight = window.frame.height
    precondition(!views(NSButton.self).contains { $0.title == "로그 열기" })
    button("고급").performClick(nil)
    precondition(window.frame.height > smallHeight)
    precondition(views(NSButton.self).contains { $0.title == "설정 파일 열기" })
    button("고급").performClick(nil)
    precondition(abs(window.frame.height - smallHeight) < 1)
    name.stringValue = "unsaved"
    window.performClose(nil)
    perform("설정…")
    precondition(name.stringValue == "Sample Phone")
    name.stringValue = "   "
    button("저장").performClick(nil)
    precondition(window.isVisible)
    precondition(views(NSTextField.self).contains { $0.stringValue == "휴대폰 핫스팟 이름을 입력하세요." })
    precondition(DotenvConfig.load(path: config.configPath).appSettings().hotspotSSID == "Sample Phone")

    // Preserve meaningful spaces in the actual SSID when checking blank input.
    name.stringValue = " Test Phone "
    let language = views(NSPopUpButton.self).first { $0.itemTitles.contains("한국어") }!
    language.selectItem(withTitle: "English")
    _ = language.sendAction(language.action, to: language.target)
    button("Save").performClick(nil)
    let deadline = Date().addingTimeInterval(4)
    while window.isVisible && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    let saved = DotenvConfig.load(path: config.configPath).appSettings()
    precondition(!window.isVisible && saved.language == "en" && saved.hotspotSSID == " Test Phone ")
    precondition(menu.items.contains { $0.title == "Settings…" })
    ui.apply(summary: .unavailable("timeout"))
    precondition(visibleTitles() == ["Waiting for Proxy", "The connection timed out.", "Reconnect Now", "Settings…", "Quit"])
    print("ok - AppKit menu actions, retry guidance, settings disclosure, SSID validation, draft discard and live menu language")
}
