import SwiftUI
import Sparkle
import PaperCore

/// Sparkle owns scheduling, consent, signature verification and atomic replacement.
@MainActor final class AppUpdateController: ObservableObject {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheck = false
    private var started = false
    var updater: SPUUpdater { controller.updater }

    init() {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }
    func start() {
        guard !started, !ProcessInfo.processInfo.arguments.contains("--self-test") else { return }
        started = true
        controller.startUpdater()
    }
    func check() { controller.checkForUpdates(nil) }
}

struct UpdateSettingsView: View {
    @ObservedObject var updates: AppUpdateController
    @State private var automatic = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("软件更新")).font(.system(size: 20, weight: .semibold))
            Text("Paper Reader \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
            Toggle(L("自动检查更新"), isOn: $automatic)
                .onChange(of: automatic) { _, value in
                    if value != updates.updater.automaticallyChecksForUpdates { updates.updater.automaticallyChecksForUpdates = value }
                }
            Button(L("检查更新…")) { updates.check() }.disabled(!updates.canCheck)
            Link(L("访问官网"), destination: URL(string: "https://www.weitao-jiang.cn/paper-reader/")!)
            Text(L("更新通过 HTTPS 下载，并在安装前验证签名。自动检查可随时关闭。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }.font(.system(size: 14)).padding(28).frame(width: 480, alignment: .leading)
            .onAppear { automatic = updates.updater.automaticallyChecksForUpdates }
    }
}
