//
//  AppPreferenceKeys.swift
//  MMH
//
//  UserDefaults keys for app preferences.
//

import Foundation

nonisolated enum AppPreferenceKeys {
    static let autoLockWhenInactive = "MMH.Preference.AutoLockWhenInactive"
    static let autoLockDelaySeconds = "MMH.Preference.AutoLockDelaySeconds"
    static let revealInFinderAfterDecrypt = "MMH.Preference.RevealInFinderAfterDecrypt"
    static let appLanguage = "MMH.Preference.AppLanguage"
}

nonisolated enum AppPreferenceDefaults {
    static func register() {
        migrateAutoLockPreferenceIfNeeded()

        UserDefaults.standard.register(defaults: [
            AppPreferenceKeys.autoLockWhenInactive: true,
            AppPreferenceKeys.autoLockDelaySeconds: AutoLockDelay.fiveMinutes.rawValue,
            AppPreferenceKeys.revealInFinderAfterDecrypt: true,
            AppPreferenceKeys.appLanguage: AppLanguage.system.rawValue
        ])
    }

    private static func migrateAutoLockPreferenceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppPreferenceKeys.autoLockDelaySeconds) == nil,
              defaults.object(forKey: AppPreferenceKeys.autoLockWhenInactive) != nil else {
            return
        }

        let oldPreferenceEnabled = defaults.bool(forKey: AppPreferenceKeys.autoLockWhenInactive)
        defaults.set(
            oldPreferenceEnabled ? AutoLockDelay.fiveMinutes.rawValue : AutoLockDelay.never.rawValue,
            forKey: AppPreferenceKeys.autoLockDelaySeconds
        )
    }
}

nonisolated enum AutoLockDelay: Int, CaseIterable, Identifiable {
    case never = 0
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .never:
            return L10n.text("autoLockNever")
        case .thirtySeconds:
            return L10n.text("autoLockAfter30Seconds")
        case .oneMinute:
            return L10n.text("autoLockAfter1Minute")
        case .fiveMinutes:
            return L10n.text("autoLockAfter5Minutes")
        case .fifteenMinutes:
            return L10n.text("autoLockAfter15Minutes")
        }
    }
}
