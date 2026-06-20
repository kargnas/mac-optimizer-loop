import Foundation

@MainActor
final class AdvisorLoop {
    private let intervalSeconds: Int
    private let action: () async -> Void
    private var timer: Timer?

    init(intervalSeconds: Int, action: @escaping () async -> Void) {
        self.intervalSeconds = max(60, intervalSeconds)
        self.action = action
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fire()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fireNow() {
        Task { @MainActor in
            await fire()
        }
    }

    private func fire() async {
        await action()
    }
}
