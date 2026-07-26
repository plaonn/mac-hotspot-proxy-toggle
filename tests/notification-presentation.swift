import Darwin
import UserNotifications

@main
struct NotificationPresentationTest {
    static func main() {
        let options = NotificationPresenter.foregroundOptions
        guard options.contains(.banner), options.contains(.list) else {
            fputs("foreground notification options must include banner and list\n", stderr)
            exit(1)
        }

        print("ok - foreground notification policy includes banner and list")
    }
}
