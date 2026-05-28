//
//  MMHApp.swift
//  MMH
//
//  Created by Roger on 2026-05-26.
//

import SwiftUI
import AppKit
import Darwin

@main
struct MMHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authViewModel: AuthViewModel

    init() {
        if CommandLine.arguments.contains("--reset-state") {
            AppStateResetter.reset()
            exit(0)
        }

        AppPreferenceDefaults.register()
        TempFileService().cleanupAll()
        _authViewModel = StateObject(wrappedValue: AuthViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 340, height: 220)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        TempFileService().cleanupAll()
    }
}

private enum AppStateResetter {
    static func reset() {
        let defaults = UserDefaults.standard
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }

        defaults.synchronize()

        let keychain = KeychainService()
        try? keychain.delete(.passwordSalt)
        try? keychain.delete(.passwordVerifier)

        TempFileService().cleanupAll()
    }
}
