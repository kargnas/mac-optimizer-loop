import AppKit
import MacOptimizingLooperCore

/// Shows the full stdout/stderr/exit-code of a user-run command. One reusable
/// window: a later result replaces the text instead of stacking windows.
@MainActor
final class CommandResultWindowController: NSWindowController {
    private let textView = NSTextView()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 240)
        self.init(window: window)
        configureTextView()
    }

    private func configureTextView() {
        guard let window else { return }
        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        textView.isEditable = false
        // Selectable so the user can drag-copy the output, per the terminal-UX rule.
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        window.contentView = scrollView
    }

    func present(result: CommandExecutionResult, strings: AppStrings) {
        window?.title = strings.resultWindowTitle
        textView.string = Self.renderText(result: result, strings: strings)
        textView.scrollToBeginningOfDocument(nil)

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    static func renderText(result: CommandExecutionResult, strings: AppStrings) -> String {
        var lines: [String] = ["$ \(result.command)", ""]

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if stdout.isEmpty && stderr.isEmpty {
            lines.append(strings.noOutput)
        } else {
            if !stdout.isEmpty { lines.append(stdout) }
            if !stderr.isEmpty {
                if !stdout.isEmpty { lines.append("") }
                lines.append("stderr:")
                lines.append(stderr)
            }
        }

        lines.append("")
        lines.append("──────────")
        let duration = String(format: "%.1fs", max(0, result.durationSeconds))
        lines.append("\(strings.exitCodeLabel): \(result.exitCode) · \(duration)")
        if result.usedAdministrator {
            lines.append(strings.ranWithAdministrator)
        }
        return lines.joined(separator: "\n")
    }
}
