//
//  VaultViewModel.swift
//  MMH
//
//  Coordinates the vault list and metadata persistence.
//

import Combine
import CryptoKit
import Foundation
import AppKit

@MainActor
final class VaultViewModel: ObservableObject {
    @Published private(set) var items: [VaultItem] = []
    @Published private(set) var folders: [VaultFolder] = []
    @Published var selectedFolderID: UUID?
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var importProgressMessage: String?
    @Published var importProgressValue: Double?
    @Published var activeFolderOperationID: UUID?
    @Published var activeFolderOperationMessage: String?
    @Published var activeFolderOperationProgressValue: Double?
    @Published var passwordChangeProgressMessage: String?
    @Published var isImporting = false
    @Published var isExporting = false
    @Published var activePreview: VaultPreview?
    @Published var sortOption: VaultSortOption = .importDate
    @Published private(set) var imageThumbnails: [UUID: NSImage] = [:]

    private let storageService: VaultStorageService
    private let cryptoService: CryptoService
    private let tempFileService: TempFileService

    init(
        storageService: VaultStorageService = VaultStorageService(),
        cryptoService: CryptoService = CryptoService(),
        tempFileService: TempFileService = TempFileService()
    ) {
        self.storageService = storageService
        self.cryptoService = cryptoService
        self.tempFileService = tempFileService
    }

    func loadItems(using key: SymmetricKey?) {
        do {
            var metadata = try storageService.loadVault(using: key)
            if metadata.items.contains(where: { $0.folderID == nil }) {
                let legacyFolderID = UUID()
                let legacyFolder = VaultFolder(
                    id: legacyFolderID,
                    name: Self.uniqueFolderName(
                        baseName: "Imported Files",
                        existingNames: Set(metadata.folders.map(\.name))
                    )
                )
                metadata.items = metadata.items.map { item in
                    item.folderID == nil ? item.moved(to: legacyFolderID) : item
                }
                metadata.folders.append(legacyFolder)

                if let key {
                    try storageService.saveVault(metadata, using: key)
                }
            }

            items = metadata.items
            folders = metadata.folders
            if let selectedFolderID, !folders.contains(where: { $0.id == selectedFolderID }) {
                self.selectedFolderID = nil
            }
            if selectedFolderID == nil {
                selectedFolderID = folders.first?.id
            }
            errorMessage = nil
            statusMessage = nil
            refreshThumbnails(using: key)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveItems(using key: SymmetricKey?) {
        do {
            try storageService.saveVault(currentMetadata, using: key)
            errorMessage = nil
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFiles(at urls: [URL], using key: SymmetricKey?) async {
        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        isImporting = true
        errorMessage = nil
        statusMessage = nil
        defer {
            isImporting = false
            importProgressMessage = nil
            importProgressValue = nil
        }

        var importedCount = 0
        var skippedCount = 0
        var duplicateCount = 0
        var lastErrorMessage: String?

        for (index, url) in urls.enumerated() {
            importProgressMessage = "Importing \(index + 1)/\(urls.count)"

            do {
                let existingHashes = Set(items.compactMap(\.contentHash))
                let result = try await Self.prepareImport(
                    at: url,
                    using: key,
                    existingHashes: existingHashes,
                    folderID: selectedFolderID,
                    cryptoService: cryptoService
                )

                let pendingImport: PendingImport
                switch result {
                case .imported(let importResult):
                    pendingImport = importResult
                case .unsupported:
                    skippedCount += 1
                    continue
                case .duplicate:
                    skippedCount += 1
                    duplicateCount += 1
                    continue
                }

                let updatedItems = items + [pendingImport.item]
                try await Self.commitImport(
                    pendingImport,
                    items: updatedItems,
                    folders: folders,
                    key: key,
                    storageService: storageService
                )

                items = updatedItems
                refreshThumbnail(for: pendingImport.item, using: key)
                importedCount += 1
            } catch {
                skippedCount += 1
                lastErrorMessage = error.localizedDescription
            }
        }

        if importedCount > 0 {
            statusMessage = "Imported \(importedCount) file(s)."
            if skippedCount > 0 {
                errorMessage = duplicateCount > 0
                    ? "Skipped \(skippedCount) file(s), including \(duplicateCount) duplicate file(s)."
                    : "Skipped \(skippedCount) file(s)."
            } else {
                errorMessage = nil
            }
        } else if let lastErrorMessage {
            errorMessage = lastErrorMessage
        } else if duplicateCount > 0 {
            errorMessage = "This file is already in the vault."
        } else if skippedCount > 0 {
            errorMessage = "No supported image or video files were imported."
        }
    }

    func importFolders(
        at urls: [URL],
        parentBookmarkDataByPath: [String: Data] = [:],
        using key: SymmetricKey?
    ) async {
        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        isImporting = true
        errorMessage = nil
        statusMessage = nil
        defer {
            isImporting = false
            importProgressMessage = nil
            importProgressValue = nil
        }

        var importedCount = 0
        var skippedCount = 0
        var removalWarningCount = 0
        var lastErrorMessage: String?

        for (index, url) in urls.enumerated() {
            importProgressMessage = L10n.format("encryptingFolderProgress", index + 1, urls.count)

            do {
                let pendingImport = try await Self.prepareFolderImport(
                    at: url,
                    using: key,
                    existingFolderNames: Set(folders.map(\.name)),
                    decryptedFolderPath: try storageService.vaultDirectoryURL()
                        .appendingPathComponent(url.lastPathComponent, isDirectory: true)
                        .standardizedFileURL
                        .path,
                    parentBookmarkData: parentBookmarkDataByPath[url.standardizedFileURL.path],
                    cryptoService: cryptoService,
                    progress: folderEncryptionProgressHandler()
                )

                guard !pendingImport.items.isEmpty || !pendingImport.folder.directoryPaths.isEmpty else {
                    skippedCount += 1
                    continue
                }

                let updatedItems = items + pendingImport.items.map(\.item)
                let updatedFolders = folders + [pendingImport.folder]

                try await Self.commitFolderImport(
                    pendingImport,
                    items: updatedItems,
                    folders: updatedFolders,
                    key: key,
                    storageService: storageService
                )

                do {
                    try await Self.deleteExternalFolder(
                        at: url,
                        parentBookmarkData: parentBookmarkDataByPath[url.standardizedFileURL.path],
                        vaultDirectoryURL: try? storageService.vaultDirectoryURL()
                    )
                } catch {
                    removalWarningCount += 1
                    lastErrorMessage = L10n.format("encryptedButDeleteFailed", error.localizedDescription)
                }

                items = updatedItems
                folders = updatedFolders
                selectedFolderID = pendingImport.folder.id
                try storageService.deleteUnreferencedEncryptedData(
                    keeping: Set(items.map(\.encryptedFileName))
                )
                importedCount += 1
            } catch {
                skippedCount += 1
                lastErrorMessage = error.localizedDescription
            }
        }

        if importedCount > 0 {
            statusMessage = L10n.format("encryptedFoldersCount", importedCount)
            if removalWarningCount > 0 {
                errorMessage = lastErrorMessage
            } else {
                errorMessage = skippedCount > 0 ? L10n.format("skippedFoldersCount", skippedCount) : nil
            }
        } else if let lastErrorMessage {
            errorMessage = lastErrorMessage
        } else if skippedCount > 0 {
            errorMessage = L10n.text("noFoldersEncrypted")
        }
    }

    func isDecrypted(_ folder: VaultFolder) -> Bool {
        guard let path = folder.decryptedFolderPath else {
            return false
        }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var sortedItems: [VaultItem] {
        let visibleItems = items.filter { item in
            guard let selectedFolderID else {
                return true
            }

            return item.folderID == selectedFolderID
        }

        switch sortOption {
        case .name:
            return visibleItems.sorted {
                $0.originalFileName.localizedCaseInsensitiveCompare($1.originalFileName) == .orderedAscending
            }
        case .importDate:
            return visibleItems.sorted { $0.importedAt > $1.importedAt }
        case .type:
            return visibleItems.sorted {
                if $0.fileType == $1.fileType {
                    return $0.originalFileName.localizedCaseInsensitiveCompare($1.originalFileName) == .orderedAscending
                }
                return $0.fileType.displayName < $1.fileType.displayName
            }
        }
    }

    var selectedFolderName: String {
        guard let selectedFolderID,
              let folder = folders.first(where: { $0.id == selectedFolderID }) else {
            return "All Files"
        }

        return folder.name
    }

    var currentMetadata: VaultMetadata {
        VaultMetadata(items: items, folders: folders)
    }

    func itemCount(in folder: VaultFolder?) -> Int {
        guard let folder else {
            return items.count
        }

        return items.filter { $0.folderID == folder.id }.count
    }

    func createFolder(named name: String, using key: SymmetricKey?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a folder name."
            return
        }

        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        guard !folders.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            errorMessage = "A folder with that name already exists."
            return
        }

        do {
            let folder = VaultFolder(name: trimmedName)
            let updatedFolders = folders + [folder]
            try storageService.saveVault(VaultMetadata(items: items, folders: updatedFolders), using: key)
            folders = updatedFolders
            selectedFolderID = folder.id
            errorMessage = nil
            statusMessage = "Created \(folder.name)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteFolder(_ folder: VaultFolder, using key: SymmetricKey?) {
        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        let itemsToDelete = items.filter { $0.folderID == folder.id }
        let updatedFolders = folders.filter { $0.id != folder.id }
        let updatedItems = items.filter { $0.folderID != folder.id }

        Task {
            do {
                try await Self.deleteItems(
                    itemsToDelete,
                    currentItems: items,
                    updatedItems: updatedItems,
                    folders: updatedFolders,
                    key: key,
                    storageService: storageService
                )
                items = updatedItems
                folders = updatedFolders
                if selectedFolderID == folder.id {
                    selectedFolderID = folders.first?.id
                }
                for item in itemsToDelete {
                    imageThumbnails[item.id] = nil
                }
                errorMessage = nil
                statusMessage = L10n.format("deletedEncryptedFolder", folder.name)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func move(_ item: VaultItem, to folderID: UUID?, using key: SymmetricKey?) {
        move(itemIDs: [item.id], to: folderID, using: key)
    }

    func move(itemIDs: Set<UUID>, to folderID: UUID?, using key: SymmetricKey?) {
        guard !itemIDs.isEmpty else {
            return
        }

        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        let updatedItems = items.map { existingItem in
            itemIDs.contains(existingItem.id) ? existingItem.moved(to: folderID) : existingItem
        }

        do {
            try storageService.saveVault(VaultMetadata(items: updatedItems, folders: folders), using: key)
            items = updatedItems
            errorMessage = nil
            statusMessage = itemIDs.count == 1 ? "Moved 1 file." : "Moved \(itemIDs.count) files."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func preview(_ item: VaultItem, using key: SymmetricKey?) async {
        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        do {
            closePreview()

            let previewURL = try await Self.makePreviewURL(
                for: item,
                using: key,
                storageService: storageService,
                cryptoService: cryptoService,
                tempFileService: tempFileService
            )

            activePreview = VaultPreview(item: item, fileURL: previewURL)
            errorMessage = nil
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export(_ item: VaultItem, to destinationURL: URL, using key: SymmetricKey?) async {
        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        do {
            try await Self.exportItem(
                item,
                to: destinationURL,
                using: key,
                storageService: storageService,
                cryptoService: cryptoService
            )
            errorMessage = nil
            statusMessage = "Exported \(item.originalFileName)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export(_ folder: VaultFolder, to destinationURL: URL, using key: SymmetricKey?) async {
        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        isExporting = true
        activeFolderOperationID = folder.id
        activeFolderOperationMessage = L10n.format("decryptingNamedFolder", folder.name)
        activeFolderOperationProgressValue = nil
        errorMessage = nil
        statusMessage = nil
        defer {
            isExporting = false
            activeFolderOperationID = nil
            activeFolderOperationMessage = nil
            activeFolderOperationProgressValue = nil
        }

        do {
            let parentBookmarkData = try Self.bookmarkData(for: destinationURL)
            let folderItems = items.filter { $0.folderID == folder.id }
            let exportedURL = try await Self.exportFolder(
                folder,
                items: folderItems,
                to: destinationURL,
                using: key,
                storageService: storageService,
                cryptoService: cryptoService,
                progress: folderOperationProgressHandler(messageKey: "decryptingFilesProgress")
            )
            try saveDecryptedLocation(
                exportedURL.path,
                parentBookmarkData: parentBookmarkData,
                for: folder,
                using: key
            )
            revealInFinderIfNeeded(exportedURL)
            errorMessage = nil
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore(_ folder: VaultFolder, using key: SymmetricKey?) async {
        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        isExporting = true
        errorMessage = nil
        statusMessage = nil
        defer {
            isExporting = false
        }

        do {
            let parentURL = try storageService.vaultDirectoryURL()
            let folderItems = items.filter { $0.folderID == folder.id }
            let exportedURL = try await Self.exportFolder(
                folder,
                items: folderItems,
                to: parentURL,
                using: key,
                storageService: storageService,
                cryptoService: cryptoService
            )
            let parentBookmarkData = folder.decryptedParentBookmarkData ?? (try? Self.bookmarkData(for: parentURL))
            try saveDecryptedLocation(
                exportedURL.path,
                parentBookmarkData: parentBookmarkData,
                for: folder,
                using: key
            )
            revealInFinderIfNeeded(exportedURL)
            errorMessage = nil
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func encryptExternalCopy(_ folder: VaultFolder, using key: SymmetricKey?) async {
        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        guard let path = folder.decryptedFolderPath else {
            errorMessage = L10n.text("noDecryptedFolderLocation")
            return
        }

        let externalURL = URL(fileURLWithPath: path, isDirectory: true)
        guard isDecrypted(folder) else {
            statusMessage = nil
            errorMessage = nil
            return
        }

        isImporting = true
        importProgressMessage = L10n.format("encryptingNamedFolder", folder.name)
        activeFolderOperationID = folder.id
        activeFolderOperationMessage = L10n.format("encryptingNamedFolder", folder.name)
        activeFolderOperationProgressValue = nil
        errorMessage = nil
        statusMessage = nil
        defer {
            isImporting = false
            importProgressMessage = nil
            importProgressValue = nil
            activeFolderOperationID = nil
            activeFolderOperationMessage = nil
            activeFolderOperationProgressValue = nil
        }

        do {
            let parentBookmarkData = folder.decryptedParentBookmarkData ??
                (try? Self.bookmarkData(for: externalURL.deletingLastPathComponent()))
            let pendingRefresh = try await Self.prepareFolderRefresh(
                at: externalURL,
                folder: folder,
                parentBookmarkData: parentBookmarkData,
                vaultDirectoryURL: try? storageService.vaultDirectoryURL(),
                using: key,
                cryptoService: cryptoService,
                progress: folderOperationProgressHandler(messageKey: "encryptingFilesProgress")
            )
            let updatedItems = items.filter { $0.folderID != folder.id } + pendingRefresh.items.map(\.item)
            let updatedFolders = folders.map { existingFolder in
                existingFolder.id == folder.id ? pendingRefresh.folder : existingFolder
            }

            try await Self.commitFolderRefresh(
                pendingRefresh,
                updatedItems: updatedItems,
                updatedFolders: updatedFolders,
                key: key,
                storageService: storageService
            )

            items = updatedItems
            folders = updatedFolders
            selectedFolderID = folder.id

            try await Self.deleteExternalFolder(
                at: externalURL,
                parentBookmarkData: parentBookmarkData,
                vaultDirectoryURL: try? storageService.vaultDirectoryURL()
            )
            try storageService.deleteUnreferencedEncryptedData(
                keeping: Set(updatedItems.map(\.encryptedFileName))
            )

            errorMessage = nil
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reencryptVault(
        from oldKey: SymmetricKey,
        to newKey: SymmetricKey,
        successMessage: String? = L10n.text("masterPasswordChanged")
    ) async throws {
        passwordChangeProgressMessage = L10n.text("preparingVault")
        defer { passwordChangeProgressMessage = nil }

        var reencryptedFiles: [ReencryptedFile] = []
        for (index, item) in items.enumerated() {
            passwordChangeProgressMessage = L10n.format("reencryptingProgress", index + 1, items.count)
            let file = try await Self.reencryptFile(
                item,
                from: oldKey,
                to: newKey,
                storageService: storageService,
                cryptoService: cryptoService
            )
            reencryptedFiles.append(file)
        }

        passwordChangeProgressMessage = L10n.text("savingVault")
        try await Self.commitReencryptedVault(
            files: reencryptedFiles,
            items: items,
            folders: folders,
            oldKey: oldKey,
            newKey: newKey,
            storageService: storageService
        )

        statusMessage = successMessage
        errorMessage = nil
    }

    func delete(_ item: VaultItem, using key: SymmetricKey?) {
        delete(itemIDs: [item.id], using: key)
    }

    func delete(itemIDs: Set<UUID>, using key: SymmetricKey?) {
        guard let key else {
            errorMessage = L10n.text("vaultLocked")
            return
        }

        let itemsToDelete = items.filter { itemIDs.contains($0.id) }
        guard !itemsToDelete.isEmpty else {
            return
        }

        Task {
            await deleteItems(itemsToDelete, using: key)
        }
    }

    func closePreview() {
        tempFileService.cleanup(activePreview?.fileURL)
        activePreview = nil
    }

    func cleanupTempFiles() {
        closePreview()
        tempFileService.cleanupAll()
    }

    private func deleteItems(_ itemsToDelete: [VaultItem], using key: SymmetricKey) async {
        let itemIDs = Set(itemsToDelete.map(\.id))
        if let activePreview, itemIDs.contains(activePreview.item.id) {
            closePreview()
        }

        let updatedItems = items.filter { !itemIDs.contains($0.id) }

        do {
            try await Self.deleteItems(
                itemsToDelete,
                currentItems: items,
                updatedItems: updatedItems,
                folders: folders,
                key: key,
                storageService: storageService
            )

            items = updatedItems
            for itemID in itemIDs {
                imageThumbnails[itemID] = nil
            }
            errorMessage = nil
            statusMessage = itemsToDelete.count == 1
                ? L10n.format("deletedOneFile", itemsToDelete[0].originalFileName)
                : L10n.format("deletedFilesCount", itemsToDelete.count)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshThumbnails(using key: SymmetricKey?) {
        imageThumbnails = [:]

        for item in items where item.fileType == .image {
            refreshThumbnail(for: item, using: key)
        }
    }

    func refreshThumbnail(for item: VaultItem, using key: SymmetricKey?) {
        guard item.fileType == .image, let key else {
            return
        }

        Task {
            do {
                let image = try await Self.makeThumbnail(
                    for: item,
                    using: key,
                    storageService: storageService,
                    cryptoService: cryptoService
                )
                imageThumbnails[item.id] = image
            } catch {
                imageThumbnails[item.id] = nil
            }
        }
    }

    private func saveDecryptedLocation(
        _ path: String,
        parentBookmarkData: Data?,
        for folder: VaultFolder,
        using key: SymmetricKey
    ) throws {
        let updatedFolder = folder.updated(
            decryptedFolderPath: path,
            decryptedParentBookmarkData: parentBookmarkData
        )
        let updatedFolders = folders.map { existingFolder in
            existingFolder.id == folder.id ? updatedFolder : existingFolder
        }
        try storageService.saveVault(VaultMetadata(items: items, folders: updatedFolders), using: key)
        folders = updatedFolders
    }

    private func revealInFinderIfNeeded(_ url: URL) {
        let shouldReveal = UserDefaults.standard.object(forKey: AppPreferenceKeys.revealInFinderAfterDecrypt) as? Bool ?? true
        guard shouldReveal else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func folderEncryptionProgressHandler() -> ((Int, Int) async -> Void) {
        { [weak self] completed, total in
            await MainActor.run {
                guard let self else {
                    return
                }

                guard total > 0 else {
                    self.importProgressValue = nil
                    self.importProgressMessage = L10n.text("scanningFolder")
                    return
                }

                self.importProgressValue = Double(completed) / Double(total)
                self.importProgressMessage = L10n.format("encryptingFilesProgress", completed, total)
            }
        }
    }

    private func folderOperationProgressHandler(messageKey: String) -> ((Int, Int) async -> Void) {
        { [weak self] completed, total in
            await MainActor.run {
                guard let self else {
                    return
                }

                guard total > 0 else {
                    self.activeFolderOperationProgressValue = nil
                    return
                }

                self.activeFolderOperationProgressValue = Double(completed) / Double(total)
                self.activeFolderOperationMessage = L10n.format(messageKey, completed, total)
            }
        }
    }

    private nonisolated static func prepareImport(
        at url: URL,
        using key: SymmetricKey,
        existingHashes: Set<String>,
        folderID: UUID?,
        cryptoService: CryptoService
    ) async throws -> ImportPreparationResult {
        try await Task.detached(priority: .userInitiated) {
            let fileType = FileTypeHelper.fileType(for: url)
            guard fileType != .unknown else {
                return .unsupported
            }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let originalData = try Data(contentsOf: url)
            let contentHash = Self.sha256Hex(for: originalData)
            if existingHashes.contains(contentHash) {
                return .duplicate
            }

            let encryptedData = try cryptoService.encrypt(originalData, using: key)
            let encryptedFileName = "\(UUID().uuidString).mmh"

            let item = VaultItem(
                originalFileName: url.lastPathComponent,
                encryptedFileName: encryptedFileName,
                fileType: fileType,
                originalExtension: url.pathExtension,
                encryptedFileSize: Int64(encryptedData.count),
                contentHash: contentHash,
                folderID: folderID
            )

            return .imported(PendingImport(item: item, encryptedData: encryptedData))
        }.value
    }

    private nonisolated static func prepareFolderImport(
        at url: URL,
        using key: SymmetricKey,
        existingFolderNames: Set<String>,
        decryptedFolderPath: String,
        parentBookmarkData: Data?,
        cryptoService: CryptoService,
        progress: ((Int, Int) async -> Void)? = nil
    ) async throws -> PendingFolderImport {
        try await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw VaultViewModelError.folderRequired
            }

            let folderID = UUID()
            let basePath = url.standardizedFileURL.path
            let folderName = Self.uniqueFolderName(
                baseName: url.lastPathComponent,
                existingNames: existingFolderNames
            )
            var pendingFiles: [PendingImport] = []
            let scannedFolder = try Self.scanFolder(at: url, basePath: basePath)
            await progress?(0, scannedFolder.files.count)

            for (index, scannedFile) in scannedFolder.files.enumerated() {
                let originalData = try Data(contentsOf: scannedFile.url)
                let encryptedData = try cryptoService.encrypt(originalData, using: key)
                let encryptedFileName = "\(UUID().uuidString).mmh"
                let item = VaultItem(
                    originalFileName: scannedFile.relativePath,
                    encryptedFileName: encryptedFileName,
                    fileType: FileTypeHelper.fileType(for: scannedFile.url),
                    originalExtension: scannedFile.url.pathExtension,
                    encryptedFileSize: Int64(encryptedData.count),
                    contentHash: Self.sha256Hex(for: originalData),
                    folderID: folderID
                )
                pendingFiles.append(PendingImport(item: item, encryptedData: encryptedData))
                await progress?(index + 1, scannedFolder.files.count)
            }

            let folder = VaultFolder(
                id: folderID,
                name: folderName,
                directoryPaths: scannedFolder.directoryPaths.sorted(),
                decryptedFolderPath: decryptedFolderPath,
                decryptedParentBookmarkData: parentBookmarkData
            )
            return PendingFolderImport(folder: folder, items: pendingFiles)
        }.value
    }

    private nonisolated static func prepareFolderRefresh(
        at url: URL,
        folder: VaultFolder,
        parentBookmarkData: Data?,
        vaultDirectoryURL: URL?,
        using key: SymmetricKey,
        cryptoService: CryptoService,
        progress: ((Int, Int) async -> Void)? = nil
    ) async throws -> PendingFolderImport {
        try await Task.detached(priority: .userInitiated) {
            let scopedURL = try parentBookmarkData.map { try Self.resolveBookmark($0) } ?? url
            let didAccess = scopedURL.startAccessingSecurityScopedResource()
            let didAccessFolder = url.startAccessingSecurityScopedResource()
            let didAccessVault = vaultDirectoryURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if didAccess {
                    scopedURL.stopAccessingSecurityScopedResource()
                }
                if didAccessFolder {
                    url.stopAccessingSecurityScopedResource()
                }
                if didAccessVault {
                    vaultDirectoryURL?.stopAccessingSecurityScopedResource()
                }
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw VaultViewModelError.folderUnavailable
            }

            let basePath = url.standardizedFileURL.path
            var pendingFiles: [PendingImport] = []
            let scannedFolder = try Self.scanFolder(at: url, basePath: basePath)
            await progress?(0, scannedFolder.files.count)

            for (index, scannedFile) in scannedFolder.files.enumerated() {
                Self.makeRemovable(scannedFile.url, isDirectory: false)
                let originalData = try Data(contentsOf: scannedFile.url)
                let encryptedData = try cryptoService.encrypt(originalData, using: key)
                let encryptedFileName = "\(UUID().uuidString).mmh"
                let item = VaultItem(
                    originalFileName: scannedFile.relativePath,
                    encryptedFileName: encryptedFileName,
                    fileType: FileTypeHelper.fileType(for: scannedFile.url),
                    originalExtension: scannedFile.url.pathExtension,
                    encryptedFileSize: Int64(encryptedData.count),
                    contentHash: Self.sha256Hex(for: originalData),
                    folderID: folder.id
                )
                pendingFiles.append(PendingImport(item: item, encryptedData: encryptedData))
                await progress?(index + 1, scannedFolder.files.count)
            }

            let refreshedFolder = VaultFolder(
                id: folder.id,
                name: folder.name,
                createdAt: folder.createdAt,
                directoryPaths: scannedFolder.directoryPaths.sorted(),
                decryptedFolderPath: url.standardizedFileURL.path,
                decryptedParentBookmarkData: parentBookmarkData ?? folder.decryptedParentBookmarkData
            )
            return PendingFolderImport(folder: refreshedFolder, items: pendingFiles)
        }.value
    }

    private nonisolated static func commitImport(
        _ pendingImport: PendingImport,
        items: [VaultItem],
        folders: [VaultFolder],
        key: SymmetricKey,
        storageService: VaultStorageService
    ) async throws {
        try await Task.detached(priority: .utility) {
            try storageService.saveEncryptedData(
                pendingImport.encryptedData,
                fileName: pendingImport.item.encryptedFileName
            )

            do {
                try storageService.saveVault(VaultMetadata(items: items, folders: folders), using: key)
            } catch {
                try? storageService.deleteEncryptedData(fileName: pendingImport.item.encryptedFileName)
                throw error
            }
        }.value
    }

    private nonisolated static func commitFolderImport(
        _ pendingImport: PendingFolderImport,
        items: [VaultItem],
        folders: [VaultFolder],
        key: SymmetricKey,
        storageService: VaultStorageService
    ) async throws {
        try await Task.detached(priority: .utility) {
            var savedFileNames: [String] = []

            do {
                for item in pendingImport.items {
                    try storageService.saveEncryptedData(
                        item.encryptedData,
                        fileName: item.item.encryptedFileName
                    )
                    savedFileNames.append(item.item.encryptedFileName)
                }

                try storageService.saveVault(VaultMetadata(items: items, folders: folders), using: key)
            } catch {
                for fileName in savedFileNames {
                    try? storageService.deleteEncryptedData(fileName: fileName)
                }
                throw error
            }
        }.value
    }

    private nonisolated static func commitFolderRefresh(
        _ pendingRefresh: PendingFolderImport,
        updatedItems: [VaultItem],
        updatedFolders: [VaultFolder],
        key: SymmetricKey,
        storageService: VaultStorageService
    ) async throws {
        try await Task.detached(priority: .utility) {
            var savedFileNames: [String] = []

            do {
                for item in pendingRefresh.items {
                    try storageService.saveEncryptedData(
                        item.encryptedData,
                        fileName: item.item.encryptedFileName
                    )
                    savedFileNames.append(item.item.encryptedFileName)
                }

                try storageService.saveVault(
                    VaultMetadata(items: updatedItems, folders: updatedFolders),
                    using: key
                )
            } catch {
                for fileName in savedFileNames {
                    try? storageService.deleteEncryptedData(fileName: fileName)
                }
                throw error
            }
        }.value
    }

    private nonisolated static func deleteEncryptedFiles(
        _ itemsToDelete: [VaultItem],
        storageService: VaultStorageService
    ) async throws {
        try await Task.detached(priority: .utility) {
            for item in itemsToDelete {
                try storageService.deleteEncryptedData(fileName: item.encryptedFileName)
            }
        }.value
    }

    private nonisolated static func makePreviewURL(
        for item: VaultItem,
        using key: SymmetricKey,
        storageService: VaultStorageService,
        cryptoService: CryptoService,
        tempFileService: TempFileService
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let encryptedData = try storageService.loadEncryptedData(fileName: item.encryptedFileName)
            let decryptedData = try cryptoService.decrypt(encryptedData, using: key)
            return try tempFileService.writePreviewData(decryptedData, for: item)
        }.value
    }

    private nonisolated static func exportItem(
        _ item: VaultItem,
        to destinationURL: URL,
        using key: SymmetricKey,
        storageService: VaultStorageService,
        cryptoService: CryptoService
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let encryptedData = try storageService.loadEncryptedData(fileName: item.encryptedFileName)
            let decryptedData = try cryptoService.decrypt(encryptedData, using: key)

            let didAccess = destinationURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    destinationURL.stopAccessingSecurityScopedResource()
                }
            }

            try decryptedData.write(to: destinationURL, options: [.atomic])
        }.value
    }

    private nonisolated static func exportFolder(
        _ folder: VaultFolder,
        items: [VaultItem],
        to destinationURL: URL,
        using key: SymmetricKey,
        storageService: VaultStorageService,
        cryptoService: CryptoService,
        progress: ((Int, Int) async -> Void)? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let didAccess = destinationURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    destinationURL.stopAccessingSecurityScopedResource()
                }
            }

            let outputURL = try Self.uniqueDirectoryURL(
                named: folder.name,
                inside: destinationURL
            )
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true
            )

            do {
                for relativePath in folder.directoryPaths where Self.isSafeRelativePath(relativePath) {
                    let directoryURL = try Self.safeChildURL(relativePath: relativePath, inside: outputURL)
                    try FileManager.default.createDirectory(
                        at: directoryURL,
                        withIntermediateDirectories: true
                    )
                }

                await progress?(0, items.count)

                for (index, item) in items.enumerated() {
                    guard Self.isSafeRelativePath(item.originalFileName) else {
                        continue
                    }

                    let fileURL = try Self.safeChildURL(
                        relativePath: item.originalFileName,
                        inside: outputURL
                    )
                    try FileManager.default.createDirectory(
                        at: fileURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    let encryptedData = try storageService.loadEncryptedData(fileName: item.encryptedFileName)
                    let decryptedData = try cryptoService.decrypt(encryptedData, using: key)
                    try decryptedData.write(to: fileURL, options: [.atomic])
                    await progress?(index + 1, items.count)
                }
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }

            return outputURL
        }.value
    }

    private nonisolated static func deleteItems(
        _ itemsToDelete: [VaultItem],
        currentItems: [VaultItem],
        updatedItems: [VaultItem],
        folders: [VaultFolder],
        key: SymmetricKey,
        storageService: VaultStorageService
    ) async throws {
        try await Task.detached(priority: .utility) {
            try storageService.saveVault(VaultMetadata(items: updatedItems, folders: folders), using: key)

            do {
                for item in itemsToDelete {
                    try storageService.deleteEncryptedData(fileName: item.encryptedFileName)
                }
            } catch {
                try? storageService.saveVault(VaultMetadata(items: currentItems, folders: folders), using: key)
                throw error
            }
        }.value
    }

    private nonisolated static func reencryptFile(
        _ item: VaultItem,
        from oldKey: SymmetricKey,
        to newKey: SymmetricKey,
        storageService: VaultStorageService,
        cryptoService: CryptoService
    ) async throws -> ReencryptedFile {
        try await Task.detached(priority: .utility) {
            let oldData = try storageService.loadEncryptedData(fileName: item.encryptedFileName)
            let decryptedData = try cryptoService.decrypt(oldData, using: oldKey)
            let newData = try cryptoService.encrypt(decryptedData, using: newKey)
            return ReencryptedFile(
                fileName: item.encryptedFileName,
                oldData: oldData,
                newData: newData
            )
        }.value
    }

    private nonisolated static func commitReencryptedVault(
        files: [ReencryptedFile],
        items: [VaultItem],
        folders: [VaultFolder],
        oldKey: SymmetricKey,
        newKey: SymmetricKey,
        storageService: VaultStorageService
    ) async throws {
        try await Task.detached(priority: .utility) {
            do {
                for file in files {
                    try storageService.saveEncryptedData(file.newData, fileName: file.fileName)
                }

                try storageService.saveVault(VaultMetadata(items: items, folders: folders), using: newKey)
            } catch {
                for file in files {
                    try? storageService.saveEncryptedData(file.oldData, fileName: file.fileName)
                }
                try? storageService.saveVault(VaultMetadata(items: items, folders: folders), using: oldKey)
                throw error
            }
        }.value
    }

    private nonisolated static func makeThumbnail(
        for item: VaultItem,
        using key: SymmetricKey,
        storageService: VaultStorageService,
        cryptoService: CryptoService
    ) async throws -> NSImage {
        try await Task.detached(priority: .utility) {
            let encryptedData = try storageService.loadEncryptedData(fileName: item.encryptedFileName)
            let decryptedData = try cryptoService.decrypt(encryptedData, using: key)
            guard let image = NSImage(data: decryptedData) else {
                throw VaultViewModelError.thumbnailUnavailable
            }
            return image
        }.value
    }

    private nonisolated static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private nonisolated static func scanFolder(at url: URL, basePath: String) throws -> ScannedFolder {
        var files: [ScannedFolderFile] = []
        var directoryPaths = Set<String>()
        var enumerationError: Error?

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw VaultViewModelError.folderUnavailable
        }

        while let fileURL = enumerator.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])

            if values.isSymbolicLink == true {
                throw VaultViewModelError.unsupportedItem(fileURL.lastPathComponent)
            }

            guard let relativePath = Self.relativePath(for: fileURL, basePath: basePath),
                  Self.isSafeRelativePath(relativePath) else {
                throw VaultViewModelError.unsafePath
            }

            if values.isDirectory == true {
                directoryPaths.insert(relativePath)
                continue
            }

            guard values.isRegularFile == true else {
                throw VaultViewModelError.unsupportedItem(fileURL.lastPathComponent)
            }

            files.append(ScannedFolderFile(url: fileURL, relativePath: relativePath))
        }

        if let enumerationError {
            throw VaultViewModelError.enumerationFailed(enumerationError.localizedDescription)
        }

        return ScannedFolder(directoryPaths: directoryPaths, files: files)
    }

    private nonisolated static func relativePath(for url: URL, basePath: String) -> String? {
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(basePath + "/") else {
            return nil
        }

        return String(filePath.dropFirst(basePath.count + 1))
    }

    private nonisolated static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            return false
        }

        return !path.split(separator: "/").contains { component in
            component == "." || component == ".."
        }
    }

    private nonisolated static func safeChildURL(relativePath: String, inside parentURL: URL) throws -> URL {
        let childURL = URL(fileURLWithPath: relativePath, relativeTo: parentURL)
            .standardizedFileURL
        let parentPath = parentURL.standardizedFileURL.path

        guard childURL.path == parentPath || childURL.path.hasPrefix(parentPath + "/") else {
            throw VaultViewModelError.unsafePath
        }

        return childURL
    }

    private nonisolated static func uniqueFolderName(
        baseName: String,
        existingNames: Set<String>
    ) -> String {
        var candidate = baseName.isEmpty ? "Encrypted Folder" : baseName
        let safeBaseName = candidate
        var index = 2

        while existingNames.contains(candidate) {
            candidate = "\(safeBaseName) \(index)"
            index += 1
        }

        return candidate
    }

    private nonisolated static func uniqueDirectoryURL(named name: String, inside parentURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let baseName = name.isEmpty ? "Decrypted Folder" : name
        var candidate = parentURL.appendingPathComponent(baseName, isDirectory: true)
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parentURL.appendingPathComponent("\(baseName) \(index)", isDirectory: true)
            index += 1
        }

        return candidate
    }

    private nonisolated static func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private nonisolated static func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private nonisolated static func deleteExternalFolder(
        at url: URL,
        parentBookmarkData: Data? = nil,
        vaultDirectoryURL: URL? = nil
    ) async throws {
        try await Task.detached(priority: .utility) {
            let scopedURL = try parentBookmarkData.map { try Self.resolveBookmark($0) } ?? url
            let didAccess = scopedURL.startAccessingSecurityScopedResource()
            let didAccessVault = vaultDirectoryURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if didAccess {
                    scopedURL.stopAccessingSecurityScopedResource()
                }
                if didAccessVault {
                    vaultDirectoryURL?.stopAccessingSecurityScopedResource()
                }
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return
            }

            try Self.deleteDirectoryTree(at: url)
        }.value
    }

    private nonisolated static func deleteDirectoryTree(at url: URL) throws {
        let fileManager = FileManager.default
        Self.makeRemovable(url, isDirectory: true)

        let children = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )

        for childURL in children {
            let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                try Self.deleteDirectoryTree(at: childURL)
            } else {
                Self.makeRemovable(childURL, isDirectory: false)
                try fileManager.removeItem(at: childURL)
            }
        }

        Self.makeRemovable(url, isDirectory: true)
        try fileManager.removeItem(at: url)
    }

    private nonisolated static func makeRemovable(_ url: URL, isDirectory: Bool) {
        let fileManager = FileManager.default
        let directoryAttributes: [FileAttributeKey: Any] = [
            .immutable: false,
            .posixPermissions: 0o700
        ]
        let fileAttributes: [FileAttributeKey: Any] = [
            .immutable: false,
            .posixPermissions: 0o600
        ]

        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isUserImmutable = false
        try? mutableURL.setResourceValues(resourceValues)

        let attributes = isDirectory ? directoryAttributes : fileAttributes
        try? fileManager.setAttributes(attributes, ofItemAtPath: url.path)
    }
}

private nonisolated struct PendingImport {
    let item: VaultItem
    let encryptedData: Data
}

private nonisolated struct PendingFolderImport {
    let folder: VaultFolder
    let items: [PendingImport]
}

private nonisolated struct ScannedFolder {
    let directoryPaths: Set<String>
    let files: [ScannedFolderFile]
}

private nonisolated struct ScannedFolderFile {
    let url: URL
    let relativePath: String
}

private nonisolated struct ReencryptedFile {
    let fileName: String
    let oldData: Data
    let newData: Data
}

private nonisolated enum ImportPreparationResult {
    case imported(PendingImport)
    case unsupported
    case duplicate
}

enum VaultSortOption: String, CaseIterable, Identifiable {
    case name = "Name"
    case importDate = "Import Date"
    case type = "Type"

    var id: String { rawValue }
}

enum VaultViewModelError: LocalizedError {
    case thumbnailUnavailable
    case folderRequired
    case folderUnavailable
    case enumerationFailed(String)
    case unsupportedItem(String)
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .thumbnailUnavailable:
            return L10n.text("thumbnailUnavailable")
        case .folderRequired:
            return L10n.text("folderRequired")
        case .folderUnavailable:
            return L10n.text("folderUnavailable")
        case .enumerationFailed(let message):
            return L10n.format("folderEnumerationFailed", message)
        case .unsupportedItem(let name):
            return L10n.format("unsupportedFolderItem", name)
        case .unsafePath:
            return L10n.text("unsafeFolderPath")
        }
    }
}

nonisolated struct VaultPreview: Identifiable {
    let id = UUID()
    let item: VaultItem
    let fileURL: URL
}
