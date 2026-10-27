import AppKit

@main
struct TimeConverterApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = appDelegate
        withExtendedLifetime(appDelegate) { application.run() }
    }
}
