//
//  VaultView.swift
//  MMH
//
//  Main unlocked vault interface.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct VaultView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPreferenceKeys.autoLockDelaySeconds) private var autoLockDelaySeconds = AutoLockDelay.fiveMinutes.rawValue
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppLanguage.system.rawValue
    @StateObject private var vaultViewModel = VaultViewModel()
    @State private var isDropTargeted = false
    @State private var isPreferencesPresented = false
    @State private var pendingDeleteFolder: VaultFolder?
    @State private var inactivityLockTask: Task<Void, Never>?
    @State private var activityMonitor: Any?
    @State private var searchText = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .overlay(vaultSeparator)

            mainBrowser
        }
        .background(vaultBackground)
        .background(StandardTrafficLightHider())
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 960, minHeight: 560)
        .onAppear {
            vaultViewModel.loadItems(using: authViewModel.currentEncryptionKey())
            startActivityMonitoring()
            resetAutoLockTimer()
        }
        .onDisappear {
            inactivityLockTask?.cancel()
            stopActivityMonitoring()
            vaultViewModel.cleanupTempFiles()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                resetAutoLockTimer()
            } else {
                resetAutoLockTimer()
            }
        }
        .onChange(of: autoLockDelaySeconds) { _, _ in
            resetAutoLockTimer()
        }
        .onChange(of: vaultViewModel.folders) { _, folders in
            if let selectedFolderID = vaultViewModel.selectedFolderID,
               !folders.contains(where: { $0.id == selectedFolderID }) {
                vaultViewModel.selectedFolderID = folders.first?.id
            } else if vaultViewModel.selectedFolderID == nil {
                vaultViewModel.selectedFolderID = folders.first?.id
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isDropTargeted,
            perform: handleDrop(providers:)
        )
        .sheet(isPresented: $isPreferencesPresented) {
            PreferencesView(
                passwordChangeProgressMessage: vaultViewModel.passwordChangeProgressMessage,
                onChangePassword: { oldPassword, newPassword, confirmation in
                    try await changeMasterPassword(
                        oldPassword: oldPassword,
                        newPassword: newPassword,
                        confirmation: confirmation
                    )
                }
            ) {
                vaultViewModel.loadItems(using: authViewModel.currentEncryptionKey())
            }
        }
        .alert(
            deleteFolderAlertTitle,
            isPresented: deleteFolderConfirmationBinding
        ) {
            Button(L10n.text("delete"), role: .destructive) {
                if let pendingDeleteFolder {
                    vaultViewModel.deleteFolder(
                        pendingDeleteFolder,
                        using: authViewModel.currentEncryptionKey()
                    )
                }
                pendingDeleteFolder = nil
            }
            Button(L10n.text("cancel"), role: .cancel) {
                pendingDeleteFolder = nil
            }
        } message: {
            Text(L10n.text("deleteEncryptedCopyMessage"))
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                MacTrafficLightControls()

                Button {
                    lockToPasswordScreen()
                } label: {
                    Label(L10n.text("lock"), systemImage: "lock.fill")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 84, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        )
                }

                Spacer()
            }
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Divider()
                .overlay(vaultSeparator)

            VStack(alignment: .leading, spacing: 18) {
                sidebarSection(
                    title: L10n.text("primaryVault").uppercased(),
                    systemImage: "externaldrive",
                    rows: [
                        SidebarRow(
                            title: L10n.text("allFiles"),
                            isSelected: true,
                            action: { vaultViewModel.selectedFolderID = filteredFolders.first?.id ?? vaultViewModel.folders.first?.id }
                        )
                    ],
                    addAction: chooseFolderToEncrypt
                )

                sidebarSection(
                    title: L10n.text("secureNotes").uppercased(),
                    systemImage: "doc.text",
                    rows: [
                        SidebarRow(
                            title: L10n.text("allNotes"),
                            isSelected: false,
                            action: { vaultViewModel.statusMessage = L10n.text("notesComingSoon") }
                        )
                    ],
                    addAction: { vaultViewModel.statusMessage = L10n.text("notesComingSoon") }
                )
            }
            .padding(.top, 18)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    isPreferencesPresented = true
                } label: {
                    Label(L10n.text("settings"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(secondaryText)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(width: 224)
        .background(sidebarBackground)
    }

    private func sidebarSection(
        title: String,
        systemImage: String,
        rows: [SidebarRow],
        addAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tertiaryText)
                .padding(.horizontal, 20)

            ForEach(rows) { row in
                Button(action: row.action) {
                    Text(row.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(row.isSelected ? Color.white : primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                        .padding(.leading, 56)
                        .background(row.isSelected ? Color.accentColor : Color.clear)
                }
                .buttonStyle(.plain)
            }

            Button(action: addAction) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tertiaryText)
                    .frame(width: 28, height: 24)
                    .padding(.leading, 52)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
    }

    private var mainBrowser: some View {
        VStack(spacing: 0) {
            browserToolbar

            Divider()
                .overlay(vaultSeparator)

            ZStack(alignment: .bottom) {
                folderBrowserContent

                if isDropTargeted {
                    dragOverlay
                }

                browserBottomBar
            }
        }
        .background(contentBackground)
    }

    private var browserToolbar: some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(VaultSortOption.allCases) { option in
                    Button {
                        vaultViewModel.sortOption = option
                    } label: {
                        if vaultViewModel.sortOption == option {
                            Label(sortTitle(option), systemImage: "checkmark")
                        } else {
                            Text(sortTitle(option))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(L10n.text("sortBy")) \(sortTitle(vaultViewModel.sortOption))")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(primaryText)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 230, alignment: .leading)

            Spacer()

            Button {
                vaultViewModel.statusMessage = L10n.text("announcementMessage")
            } label: {
                Text(L10n.text("announcement"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.47, blue: 0.20))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(red: 1.0, green: 0.47, blue: 0.20).opacity(0.8), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tertiaryText)

                TextField("", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(primaryText)
            }
            .padding(.horizontal, 10)
            .frame(width: 176, height: 31)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.32), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(toolbarBackground)
    }

    private var folderBrowserContent: some View {
        Group {
            if vaultViewModel.folders.isEmpty {
                macEmptyState(
                    title: L10n.text("noEncryptedFolders"),
                    message: L10n.text("chooseOrDragFolder"),
                    systemImage: "folder"
                )
            } else if filteredFolders.isEmpty {
                macEmptyState(
                    title: L10n.text("noSearchResults"),
                    message: L10n.text("tryAnotherSearch"),
                    systemImage: "magnifyingglass"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredFolders) { folder in
                            browserFolderRow(folder)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .padding(.bottom, 92)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func browserFolderRow(_ folder: VaultFolder) -> some View {
        let isSelected = vaultViewModel.selectedFolderID == folder.id
        let isVisible = vaultViewModel.isDecrypted(folder)

        return Button {
            vaultViewModel.selectedFolderID = folder.id
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(folderGradient)
                        .shadow(color: Color.black.opacity(0.30), radius: 2, y: 1)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Color(red: 0.34, green: 0.79, blue: 1.0))
                }
                .frame(width: 62, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text(folder.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)

                    Text(folderSubtitle(folder))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                if vaultViewModel.activeFolderOperationID == folder.id {
                    activeOperationView
                } else {
                    Text(isVisible ? L10n.text("visible") : L10n.text("hidden"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tertiaryText)

                    Toggle("", isOn: decryptedBinding(for: folder))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(isBusy)
                }

                Button {
                    vaultViewModel.selectedFolderID = folder.id
                    openFolderFromRow(folder)
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(tertiaryText)
                }
                .buttonStyle(.plain)
                .help(L10n.text("openInFinder"))
                .disabled(isBusy)
            }
            .padding(.horizontal, 14)
            .frame(height: 72)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.white.opacity(0.07) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color(red: 0.44, green: 0.53, blue: 0.68).opacity(0.95) : Color.clear, lineWidth: 1)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.text("unhideSelectedItems")) {
                Task {
                    await vaultViewModel.restore(
                        folder,
                        using: authViewModel.currentEncryptionKey()
                    )
                }
            }
            Button(L10n.text("hideSelectedItems")) {
                Task {
                    await vaultViewModel.encryptExternalCopy(
                        folder,
                        using: authViewModel.currentEncryptionKey()
                    )
                }
            }
            Divider()
            Button(L10n.text("removeSelectedItems"), role: .destructive) {
                pendingDeleteFolder = folder
            }
        }
    }

    private var activeOperationView: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(vaultViewModel.activeFolderOperationMessage ?? L10n.text("pleaseWait"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondaryText)
                .lineLimit(1)

            if let progressValue = vaultViewModel.activeFolderOperationProgressValue {
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
                    .frame(width: 150)
                    .controlSize(.small)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 150)
                    .controlSize(.small)
            }
        }
    }

    private var browserBottomBar: some View {
        HStack {
            Button {
                chooseFolderToEncrypt()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 42, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(primaryText)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
            }
            .disabled(isBusy)

            if let message = vaultViewModel.errorMessage ?? vaultViewModel.statusMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(vaultViewModel.errorMessage == nil ? Color(red: 0.58, green: 0.87, blue: 0.62) : Color(red: 1.0, green: 0.45, blue: 0.42))
                    .lineLimit(1)
                    .padding(.leading, 8)
            }

            Spacer()

            Menu {
                Button(L10n.text("unhideAllItems")) {
                    restoreAllFolders()
                }
                .disabled(vaultViewModel.folders.isEmpty || isBusy)

                Divider()

                Button(L10n.text("hideSelectedItems")) {
                    hideSelectedFolder()
                }
                .disabled(selectedFolder == nil || isBusy)

                Button(L10n.text("unhideSelectedItems")) {
                    restoreSelectedFolder()
                }
                .disabled(selectedFolder == nil || isBusy)

                Divider()

                Button(L10n.text("removeSelectedItems"), role: .destructive) {
                    if let selectedFolder {
                        pendingDeleteFolder = selectedFolder
                    }
                }
                .disabled(selectedFolder == nil || isBusy)
            } label: {
                HStack(spacing: 0) {
                    Text(L10n.text("unhideAll"))
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 14)

                    Divider()
                        .frame(height: 30)
                        .overlay(vaultSeparator)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12)
                }
                .frame(height: 30)
                .foregroundStyle(primaryText)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        )
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var dragOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.12))
            }
            .overlay {
                Label(L10n.text("dropFolderHere"), systemImage: "tray.and.arrow.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
            .padding(16)
    }

    private func macEmptyState(title: String, message: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(tertiaryText)

            Text(title)
                .font(.headline)
                .foregroundStyle(primaryText)

            Text(message)
                .font(.callout)
                .foregroundStyle(tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var filteredFolders: [VaultFolder] {
        let searchedFolders: [VaultFolder]
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if query.isEmpty {
            searchedFolders = vaultViewModel.folders
        } else {
            searchedFolders = vaultViewModel.folders.filter { folder in
                folder.name.localizedCaseInsensitiveContains(query) ||
                    vaultViewModel.items.contains { item in
                        item.folderID == folder.id &&
                            item.originalFileName.localizedCaseInsensitiveContains(query)
                    }
            }
        }

        switch vaultViewModel.sortOption {
        case .name:
            return searchedFolders.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .importDate:
            return searchedFolders.sorted { $0.createdAt > $1.createdAt }
        case .type:
            return searchedFolders.sorted {
                if vaultViewModel.isDecrypted($0) == vaultViewModel.isDecrypted($1) {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

                return vaultViewModel.isDecrypted($0) && !vaultViewModel.isDecrypted($1)
            }
        }
    }

    private var vaultBackground: Color {
        Color(red: 0.18, green: 0.18, blue: 0.19)
    }

    private var sidebarBackground: Color {
        Color(red: 0.15, green: 0.15, blue: 0.16)
    }

    private var toolbarBackground: Color {
        Color(red: 0.31, green: 0.31, blue: 0.34)
    }

    private var contentBackground: Color {
        Color(red: 0.30, green: 0.30, blue: 0.33)
    }

    private var vaultSeparator: Color {
        Color.black.opacity(0.24)
    }

    private var primaryText: Color {
        Color.white.opacity(0.86)
    }

    private var secondaryText: Color {
        Color.white.opacity(0.72)
    }

    private var tertiaryText: Color {
        Color.white.opacity(0.48)
    }

    private var folderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.44, green: 0.84, blue: 1.0),
                Color(red: 0.22, green: 0.63, blue: 0.92)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func folderSubtitle(_ folder: VaultFolder) -> String {
        L10n.format("folderRowSubtitle", encryptedSizeText(for: folder))
    }

    private func sortTitle(_ option: VaultSortOption) -> String {
        switch option {
        case .name:
            return L10n.text("sortName")
        case .importDate:
            return L10n.text("sortDateAdded")
        case .type:
            return L10n.text("sortVisibility")
        }
    }

    private func restoreAllFolders() {
        Task {
            for folder in vaultViewModel.folders where !vaultViewModel.isDecrypted(folder) {
                await vaultViewModel.restore(
                    folder,
                    using: authViewModel.currentEncryptionKey()
                )
            }
        }
    }

    private func restoreSelectedFolder() {
        guard let selectedFolder else {
            return
        }

        Task {
            await vaultViewModel.restore(
                selectedFolder,
                using: authViewModel.currentEncryptionKey()
            )
        }
    }

    private func hideSelectedFolder() {
        guard let selectedFolder else {
            return
        }

        Task {
            await vaultViewModel.encryptExternalCopy(
                selectedFolder,
                using: authViewModel.currentEncryptionKey()
            )
        }
    }

    private func openFolderFromRow(_ folder: VaultFolder) {
        if vaultViewModel.isDecrypted(folder),
           let path = folder.decryptedFolderPath {
            NSWorkspace.shared.activateFileViewerSelecting([
                URL(fileURLWithPath: path, isDirectory: true)
            ])
            return
        }

        Task {
            await vaultViewModel.restore(
                folder,
                using: authViewModel.currentEncryptionKey()
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("mmhVault"))
                    .font(.title2.weight(.semibold))

                Text(L10n.text("mainSubtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                chooseFolderToEncrypt()
            } label: {
                Label(L10n.text("encryptFolder"), systemImage: "folder.badge.plus")
            }
            .disabled(isBusy)
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                isPreferencesPresented = true
            } label: {
                Label(L10n.text("settings"), systemImage: "gearshape")
            }
            .disabled(isBusy)
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                lockToPasswordScreen()
            } label: {
                Label(L10n.text("lock"), systemImage: "lock")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func resetAutoLockTimer() {
        inactivityLockTask?.cancel()

        guard autoLockDelaySeconds > 0 else {
            return
        }

        let delayNanoseconds = UInt64(autoLockDelaySeconds) * 1_000_000_000
        inactivityLockTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            lockToPasswordScreen()
        }
    }

    private func startActivityMonitoring() {
        guard activityMonitor == nil else {
            return
        }

        activityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .keyDown,
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
                .scrollWheel
            ]
        ) { event in
            resetAutoLockTimer()
            return event
        }
    }

    private func stopActivityMonitoring() {
        if let activityMonitor {
            NSEvent.removeMonitor(activityMonitor)
            self.activityMonitor = nil
        }
    }

    private func lockToPasswordScreen() {
        inactivityLockTask?.cancel()
        stopActivityMonitoring()
        vaultViewModel.cleanupTempFiles()
        authViewModel.lock()
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isDropTargeted ? Color.accentColor : Color(NSColor.separatorColor),
                lineWidth: isDropTargeted ? 2 : 1
            )
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            }
            .overlay {
                HStack(spacing: 12) {
                    Image(systemName: isDropZoneEncrypting ? "lock.rotation" : "tray.and.arrow.down")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isDropZoneEncrypting ? (vaultViewModel.importProgressMessage ?? L10n.text("encryptingFolder")) : L10n.text("dropFolderHere"))
                            .font(.headline)

                        Text(L10n.text("dropZoneHelp"))
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if isDropZoneEncrypting {
                            if let progressValue = vaultViewModel.importProgressValue {
                                ProgressView(value: progressValue)
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: 360)
                                    .padding(.top, 6)
                            } else {
                                ProgressView()
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: 360)
                                    .padding(.top, 6)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            .frame(height: isDropZoneEncrypting ? 96 : 76)
    }

    private var isDropZoneEncrypting: Bool {
        vaultViewModel.isImporting && vaultViewModel.activeFolderOperationID == nil
    }

    private var folderWorkspace: some View {
        HStack(alignment: .top, spacing: 18) {
            encryptedFolderList
                .frame(width: 300)

            selectedFolderPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var encryptedFolderList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("encryptedFolders"))
                    .font(.headline)

                Spacer()

                Text("\(vaultViewModel.folders.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if vaultViewModel.folders.isEmpty {
                emptyFolderList
            } else {
                List(selection: $vaultViewModel.selectedFolderID) {
                    ForEach(vaultViewModel.folders) { folder in
                        folderRow(folder)
                            .tag(folder.id as UUID?)
                            .contextMenu {
                                Button(L10n.text("decrypt")) {
                                    Task {
                                        await vaultViewModel.restore(
                                            folder,
                                            using: authViewModel.currentEncryptionKey()
                                        )
                                    }
                                }

                                Button(L10n.text("deleteEncryptedFolder"), role: .destructive) {
                                    pendingDeleteFolder = folder
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyFolderList: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text(L10n.text("noEncryptedFolders"))
                .font(.headline)

            Text(L10n.text("chooseOrDragFolder"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func folderRow(_ folder: VaultFolder) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: vaultViewModel.selectedFolderID == folder.id ? "folder.fill" : "folder")
                    .foregroundStyle(.blue)

                Text(folder.name)
                    .lineLimit(1)
            }

            Text(L10n.format("filesCount", fileCount(in: folder)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var selectedFolderPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let folder = selectedFolder {
                selectedFolderDetails(folder)
            } else {
                noSelectionState
            }

            if let message = vaultViewModel.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let message = vaultViewModel.statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func selectedFolderDetails(_ folder: VaultFolder) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: vaultViewModel.isDecrypted(folder) ? "folder.fill" : "lock.doc")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 6) {
                    Text(folder.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    Text(L10n.format("encryptedDate", folder.createdAt.formatted(date: .numeric, time: .shortened)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                folderOperationControl(for: folder)
            }

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.text("files"))
                        .foregroundStyle(.secondary)
                    Text("\(fileCount(in: folder))")
                }

                GridRow {
                    Text(L10n.text("subfolders"))
                        .foregroundStyle(.secondary)
                    Text("\(folder.directoryPaths.count)")
                }

                GridRow {
                    Text(L10n.text("encryptedSize"))
                        .foregroundStyle(.secondary)
                    Text(encryptedSizeText(for: folder))
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func folderOperationControl(for folder: VaultFolder) -> some View {
        if vaultViewModel.activeFolderOperationID == folder.id {
            VStack(alignment: .leading, spacing: 7) {
                Label(
                    vaultViewModel.activeFolderOperationMessage ?? L10n.text("encryptingFolder"),
                    systemImage: vaultViewModel.isDecrypted(folder) ? "lock" : "lock.open"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

                if let progressValue = vaultViewModel.activeFolderOperationProgressValue {
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .frame(width: 210)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 210)
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 3)
        } else {
            Toggle(isOn: decryptedBinding(for: folder)) {
                Label(
                    L10n.text(vaultViewModel.isDecrypted(folder) ? "decrypted" : "encrypted"),
                    systemImage: vaultViewModel.isDecrypted(folder) ? "lock.open" : "lock"
                )
            }
            .toggleStyle(.switch)
            .disabled(isBusy)
        }
    }

    private var noSelectionState: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.doc")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text(L10n.text("selectEncryptedFolder"))
                .font(.headline)

            Text(L10n.text("folderActionsHere"))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var isBusy: Bool {
        vaultViewModel.isImporting || vaultViewModel.isExporting
    }

    private var selectedFolder: VaultFolder? {
        guard let selectedFolderID = vaultViewModel.selectedFolderID else {
            return vaultViewModel.folders.first
        }

        return vaultViewModel.folders.first { $0.id == selectedFolderID }
    }

    private var deleteFolderConfirmationBinding: Binding<Bool> {
        Binding {
            pendingDeleteFolder != nil
        } set: { isPresented in
            if !isPresented {
                pendingDeleteFolder = nil
            }
        }
    }

    private var deleteFolderAlertTitle: String {
        L10n.format(
            "deleteFolderTitle",
            pendingDeleteFolder?.name ?? L10n.text("thisEncryptedFolder")
        )
    }

    private func chooseFolderToEncrypt() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.text("encrypt")

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        encryptFolders([folderURL])
    }

    private func decryptedBinding(for folder: VaultFolder) -> Binding<Bool> {
        Binding {
            vaultViewModel.isDecrypted(folder)
        } set: { shouldDecrypt in
            set(folder, decrypted: shouldDecrypt)
        }
    }

    private func set(_ folder: VaultFolder, decrypted: Bool) {
        if decrypted {
            Task {
                await vaultViewModel.restore(
                    folder,
                    using: authViewModel.currentEncryptionKey()
                )
            }
        } else {
            Task {
                await vaultViewModel.encryptExternalCopy(
                    folder,
                    using: authViewModel.currentEncryptionKey()
                )
            }
        }
    }

    private func encryptFolders(
        _ urls: [URL],
        parentBookmarkDataByPath: [String: Data] = [:]
    ) {
        Task {
            await vaultViewModel.importFolders(
                at: urls,
                parentBookmarkDataByPath: parentBookmarkDataByPath,
                using: authViewModel.currentEncryptionKey()
            )
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let urlsLock = NSLock()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = fileURL(from: item) {
                    urlsLock.lock()
                    urls.append(url)
                    urlsLock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else {
                return
            }

            encryptFolders(urls)
        }

        return !providers.isEmpty
    }

    private func fileCount(in folder: VaultFolder) -> Int {
        vaultViewModel.items.filter { $0.folderID == folder.id }.count
    }

    private func encryptedSizeText(for folder: VaultFolder) -> String {
        let byteCount = vaultViewModel.items
            .filter { $0.folderID == folder.id }
            .compactMap(\.encryptedFileSize)
            .reduce(Int64(0), +)

        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func changeMasterPassword(
        oldPassword: String,
        newPassword: String,
        confirmation: String
    ) async throws {
        guard authViewModel.verifyMasterPassword(oldPassword) else {
            throw VaultViewError.wrongPassword
        }

        guard let oldKey = authViewModel.currentEncryptionKey() else {
            throw VaultViewError.locked
        }

        let pendingPassword = try authViewModel.makePendingMasterPassword(
            password: newPassword,
            confirmation: confirmation
        )

        try await vaultViewModel.reencryptVault(from: oldKey, to: pendingPassword.key)

        do {
            try authViewModel.commitMasterPasswordChange(pendingPassword)
        } catch {
            try? await vaultViewModel.reencryptVault(
                from: pendingPassword.key,
                to: oldKey,
                successMessage: nil
            )
            throw error
        }
    }

    private func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        return nil
    }
}

private struct SidebarRow: Identifiable {
    let id = UUID()
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

struct ChangeMasterPasswordView: View {
    let progressMessage: String?
    let onSubmit: (String, String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppLanguage.system.rawValue
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @State private var isChanging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("changeMasterPassword"))
                .font(.title2.weight(.semibold))

            VStack(spacing: 12) {
                SecureField(L10n.text("currentPassword"), text: $oldPassword)
                    .textFieldStyle(.roundedBorder)

                SecureField(L10n.text("newPassword"), text: $newPassword)
                    .textFieldStyle(.roundedBorder)

                SecureField(L10n.text("confirmNewPassword"), text: $confirmation)
                    .textFieldStyle(.roundedBorder)
            }

            if let progressMessage {
                Text(progressMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button(L10n.text("cancel")) {
                    dismiss()
                }
                .disabled(isChanging)

                Button {
                    submit()
                } label: {
                    if isChanging {
                        ProgressView()
                            .frame(width: 96)
                    } else {
                        Text(L10n.text("change"))
                            .frame(width: 96)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var canSubmit: Bool {
        !isChanging && !oldPassword.isEmpty && !newPassword.isEmpty && !confirmation.isEmpty
    }

    private func submit() {
        isChanging = true
        errorMessage = nil

        Task {
            do {
                try await onSubmit(oldPassword, newPassword, confirmation)
                oldPassword = ""
                newPassword = ""
                confirmation = ""
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isChanging = false
        }
    }
}

private struct MacTrafficLightControls: View {
    var body: some View {
        HStack(spacing: 14) {
            trafficButton(color: Color(red: 1.0, green: 0.27, blue: 0.29)) {
                currentWindow()?.performClose(nil)
            }

            trafficButton(color: Color(red: 1.0, green: 0.76, blue: 0.14)) {
                currentWindow()?.miniaturize(nil)
            }

            trafficButton(color: Color(red: 0.20, green: 0.80, blue: 0.30)) {
                currentWindow()?.zoom(nil)
            }
        }
        .frame(width: 74, height: 34, alignment: .leading)
    }

    private func trafficButton(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .shadow(color: Color.black.opacity(0.25), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .frame(width: 16, height: 24)
    }

    private func currentWindow() -> NSWindow? {
        NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
    }
}

private struct StandardTrafficLightHider: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            StandardTrafficLightHider.setTrafficLightsHidden(true, from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            StandardTrafficLightHider.setTrafficLightsHidden(true, from: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        setTrafficLightsHidden(false, from: nsView)
    }

    private static func setTrafficLightsHidden(_ isHidden: Bool, from view: NSView) {
        guard let window = view.window else {
            return
        }

        [
            .closeButton,
            .miniaturizeButton,
            .zoomButton
        ].forEach { buttonType in
            window.standardWindowButton(buttonType)?.isHidden = isHidden
        }
    }
}

private enum VaultViewError: LocalizedError {
    case locked
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .locked:
            return L10n.text("vaultLocked")
        case .wrongPassword:
            return L10n.text("wrongPassword")
        }
    }
}

struct VaultView_Previews: PreviewProvider {
    static var previews: some View {
        VaultView()
            .environmentObject(AuthViewModel())
    }
}
