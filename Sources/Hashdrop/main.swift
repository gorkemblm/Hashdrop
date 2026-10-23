import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    // `Hashdrop --render-demo <dir>` draws the README GIFs instead of starting the app.
    let args = CommandLine.arguments
    if let flag = args.firstIndex(of: "--render-demo"), args.count > flag + 1 {
        let renderer = DemoRenderer(outputDirectory: URL(fileURLWithPath: args[flag + 1]))
        app.delegate = renderer
        app.run()
    } else {
        let controller = AppController()
        app.delegate = controller
        app.run()
    }
}
