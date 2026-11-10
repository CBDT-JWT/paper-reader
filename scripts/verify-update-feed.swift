// Optional live check: reads/parses the configured HTTPS appcast without offering installation.
import AppKit
import Sparkle

@MainActor final class Probe: NSObject, SPUUpdaterDelegate {
    var loaded = false
    var expectedVersion: String?
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        loaded = true
        print("LIVE APPCAST: HTTPS feed loaded and parsed by Sparkle; items=\(appcast.items.count)")
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("LIVE APPCAST: eligible update \(item.displayVersionString), build \(item.versionString)")
        exit(loaded && (expectedVersion == nil || expectedVersion == item.versionString) ? 0 : 1)
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        print("LIVE APPCAST: valid stable feed, no eligible newer update for this host")
        exit(loaded && expectedVersion == nil ? 0 : 1)
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        print("LIVE APPCAST ERROR: \(error.localizedDescription)"); exit(1)
    }
}
try MainActor.assumeIsolated {
guard (2...3).contains(CommandLine.arguments.count), let host = Bundle(path: CommandLine.arguments[1]) else {
    print("Usage: swift -F <frameworks> -framework Sparkle -Xlinker -rpath -Xlinker <frameworks> scripts/verify-update-feed.swift <app> [expected-newer-build]"); exit(2)
}
let probe = Probe()
probe.expectedVersion = CommandLine.arguments.count == 3 ? CommandLine.arguments[2] : nil
let driver = SPUStandardUserDriver(hostBundle: host, delegate: nil)
let updater = SPUUpdater(hostBundle: host, applicationBundle: host, userDriver: driver, delegate: probe)
try updater.start()
updater.checkForUpdateInformation()
DispatchQueue.main.asyncAfter(deadline: .now() + 25) { print("LIVE APPCAST: timeout"); exit(2) }
RunLoop.main.run()

}
