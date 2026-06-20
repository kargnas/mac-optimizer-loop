import AppKit
import MacOptimizingLooperCore

@MainActor
private var retainedAppDelegate: AppDelegate?

MainActor.assumeIsolated {
    let app = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    retainedAppDelegate = delegate
    NSApp.run()
}
