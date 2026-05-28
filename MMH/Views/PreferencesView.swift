//
//  PreferencesView.swift
//  MMH
//
//  App settings for MMH.
//

import AppKit
import SwiftUI

struct PreferencesView: View {
    let passwordChangeProgressMessage: String?
    let onChangePassword: (String, String, String) async throws -> Void
    let onStorageChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferenceKeys.autoLockDelaySeconds) private var autoLockDelaySeconds = AutoLockDelay.fiveMinutes.rawValue
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppLanguage.system.rawValue
    @State private var selectedTab = PreferencesTab.general
    @State private var vaultPath = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isChangePasswordPresented = false

    private static let windowWidth: CGFloat = 500
    private static let windowHeight: CGFloat = 320
    private let storageService = VaultStorageService()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: Self.windowWidth, height: Self.windowHeight)
        .onAppear {
            refreshVaultPath()
        }
        .sheet(isPresented: $isChangePasswordPresented) {
            ChangeMasterPasswordView(
                progressMessage: passwordChangeProgressMessage,
                onSubmit: onChangePassword
            )
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 7) {
                Text(L10n.text("preferences"))
                    .font(.headline.weight(.semibold))

                Picker(L10n.text("preferences"), selection: $selectedTab) {
                    ForEach(PreferencesTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 250)
            }
        }
        .frame(width: Self.windowWidth)
        .overlay(alignment: .topLeading) {
            MacCloseButton {
                dismiss()
            }
            .help(L10n.text("close"))
            .keyboardShortcut(.cancelAction)
            .padding(.leading, 16)
            .padding(.top, 3)
        }
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general:
            generalPane
        case .security:
            securityPane
        case .storage:
            storagePane
        }
    }

    private var generalPane: some View {
        VStack(spacing: 0) {
            settingRow(L10n.text("language")) {
                Picker(L10n.text("language"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 190)
            }

            Divider()
                .padding(.vertical, 8)

            settingRow(
                L10n.text("lockWhenInactive"),
                help: L10n.text("lockWhenInactiveHelp")
            ) {
                Picker(L10n.text("lockWhenInactive"), selection: $autoLockDelaySeconds) {
                    ForEach(AutoLockDelay.allCases) { delay in
                        Text(delay.title).tag(delay.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150)
            }

            Spacer()
        }
    }

    private var securityPane: some View {
        VStack(spacing: 0) {
            settingRow(
                L10n.text("plainFoldersTrash"),
                help: L10n.text("plainFoldersTrashHelp")
            ) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.vertical, 8)

            settingRow(
                L10n.text("masterPasswordTitle"),
                help: L10n.text("masterPasswordHelp")
            ) {
                Button(L10n.text("changePassword")) {
                    isChangePasswordPresented = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()
        }
    }

    private var storagePane: some View {
        VStack(spacing: 0) {
            settingRow(
                L10n.text("encryptedStorageLocation"),
                help: L10n.text("storageHelp"),
                controlAlignment: .top
            ) {
                Button(L10n.text("change")) {
                    changeStorageLocation()
                }
                .controlSize(.small)
            }

            Text(vaultPath.isEmpty ? L10n.text("noStorageFolder") : vaultPath)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 10)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.top, 8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }

            Spacer()
        }
    }

    private func settingRow<Control: View>(
        _ title: String,
        help: String? = nil,
        controlAlignment: VerticalAlignment = .center,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: controlAlignment, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                if let help {
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            control()
        }
    }

    private func refreshVaultPath() {
        vaultPath = (try? storageService.vaultDirectoryURL().path) ?? ""
    }

    private func changeStorageLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.text("useFolder")
        panel.message = L10n.text("chooseStorageMessage")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try storageService.moveVaultDirectory(to: url)
            refreshVaultPath()
            statusMessage = L10n.text("storageUpdated")
            errorMessage = nil
            onStorageChanged()
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct MacCloseButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.38, blue: 0.34))
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                    }

                Image(systemName: "xmark")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(Color.black.opacity(isHovered ? 0.48 : 0))
            }
            .frame(width: 12, height: 12)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case security
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return L10n.text("general")
        case .security:
            return L10n.text("security")
        case .storage:
            return L10n.text("storage")
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "switch.2"
        case .security:
            return "lock.shield"
        case .storage:
            return "externaldrive"
        }
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView(
            passwordChangeProgressMessage: nil,
            onChangePassword: { _, _, _ in },
            onStorageChanged: {}
        )
    }
}
