//
//  VaultStorageService.swift
//  MMH
//
//  Owns local vault folders and JSON metadata persistence.
//

import Foundation
import CryptoKit

enum VaultStorageServiceError: LocalizedError {
    case applicationSupportDirectoryUnavailable
    case missingEncryptionKey
    case vaultDirectoryUnavailable
    case targetDirectoryAlreadyContainsVaultData

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return L10n.text("applicationSupportUnavailable")
        case .missingEncryptionKey:
            return L10n.text("vaultLocked")
        case .vaultDirectoryUnavailable:
            return L10n.text("vaultDirectoryUnavailable")
        case .targetDirectoryAlreadyContainsVaultData:
            return L10n.text("targetContainsVaultData")
        }
    }
}

nonisolated struct VaultStorageService {
    private let fileManager = FileManager.default
    private let folderName = "MMH"
    private let encryptedFolderName = "EncryptedFiles"
    private let metadataFileName = "metadata.json"
    private let vaultBookmarkKey = "MMH.VaultDirectoryBookmark"
    private let vaultPathKey = "MMH.VaultDirectoryPath"

    func hasConfiguredVaultDirectory() -> Bool {
        UserDefaults.standard.data(forKey: vaultBookmarkKey) != nil ||
            UserDefaults.standard.string(forKey: vaultPathKey) != nil
    }

    func configureVaultDirectory(_ url: URL) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        UserDefaults.standard.set(bookmarkData, forKey: vaultBookmarkKey)
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: vaultPathKey)
    }

    func vaultDirectoryURL() throws -> URL {
        try vaultRootDirectory()
    }

    func moveVaultDirectory(to newURL: URL) throws {
        let oldURL = try vaultRootDirectory()
        let oldPath = oldURL.standardizedFileURL.path
        let newPath = newURL.standardizedFileURL.path

        if oldPath == newPath {
            try configureVaultDirectory(newURL)
            return
        }

        let didAccessOld = oldURL.startAccessingSecurityScopedResource()
        let didAccessNew = newURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessOld {
                oldURL.stopAccessingSecurityScopedResource()
            }
            if didAccessNew {
                newURL.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.createDirectory(at: newURL, withIntermediateDirectories: true)

        let sourceMetadata = oldURL.appendingPathComponent(metadataFileName)
        let sourceEncrypted = oldURL.appendingPathComponent(encryptedFolderName, isDirectory: true)
        let destinationMetadata = newURL.appendingPathComponent(metadataFileName)
        let destinationEncrypted = newURL.appendingPathComponent(encryptedFolderName, isDirectory: true)

        guard !fileManager.fileExists(atPath: destinationMetadata.path),
              !fileManager.fileExists(atPath: destinationEncrypted.path) else {
            throw VaultStorageServiceError.targetDirectoryAlreadyContainsVaultData
        }

        if fileManager.fileExists(atPath: sourceMetadata.path) {
            try fileManager.moveItem(at: sourceMetadata, to: destinationMetadata)
        }

        if fileManager.fileExists(atPath: sourceEncrypted.path) {
            try fileManager.moveItem(at: sourceEncrypted, to: destinationEncrypted)
        }

        try configureVaultDirectory(newURL)
    }

    func loadVault(using key: SymmetricKey?) throws -> VaultMetadata {
        try withVaultDirectoryAccess {
            try ensureVaultDirectories()

            let url = try metadataURL()
            guard fileManager.fileExists(atPath: url.path) else {
                let metadata = VaultMetadata()
                try saveVault(metadata, using: key)
                return metadata
            }

            let data = try Data(contentsOf: url)
            if data.isEmpty {
                return VaultMetadata()
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let encryptedMetadata = try? decoder.decode(EncryptedVaultMetadata.self, from: data) {
                guard let key else {
                    throw VaultStorageServiceError.missingEncryptionKey
                }

                if let encryptedVault = encryptedMetadata.encryptedVault {
                    let decryptedData = try CryptoService().decrypt(encryptedVault, using: key)
                    return try decoder.decode(VaultMetadata.self, from: decryptedData)
                }

                if let encryptedItems = encryptedMetadata.encryptedItems {
                    let decryptedData = try CryptoService().decrypt(encryptedItems, using: key)
                    let items = try decoder.decode([VaultItem].self, from: decryptedData)
                    return VaultMetadata(items: items, folders: [])
                }
            }

            // Legacy v1 metadata stored VaultItem entries as plain JSON. It remains readable;
            // future writes use the v3 encrypted wrapper format below.
            let items = try decoder.decode([VaultItem].self, from: data)
            return VaultMetadata(items: items, folders: [])
        }
    }

    func saveVault(_ metadata: VaultMetadata, using key: SymmetricKey?) throws {
        try withVaultDirectoryAccess {
            try ensureVaultDirectories()
            guard let key else {
                throw VaultStorageServiceError.missingEncryptionKey
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let metadataData = try encoder.encode(metadata)
            let encryptedVault = try CryptoService().encrypt(metadataData, using: key)
            let data = try encoder.encode(EncryptedVaultMetadata(encryptedVault: encryptedVault))
            try data.write(to: try metadataURL(), options: [.atomic])
        }
    }

    func loadItems(using key: SymmetricKey?) throws -> [VaultItem] {
        try loadVault(using: key).items
    }

    func saveItems(_ items: [VaultItem], using key: SymmetricKey?) throws {
        try saveVault(VaultMetadata(items: items), using: key)
    }

    func encryptedFileURL(fileName: String) throws -> URL {
        try encryptedFilesDirectory().appendingPathComponent(fileName)
    }

    func saveEncryptedData(_ data: Data, fileName: String) throws {
        try withVaultDirectoryAccess {
            try ensureVaultDirectories()
            try data.write(to: encryptedFileURL(fileName: fileName), options: [.atomic])
        }
    }

    func deleteEncryptedData(fileName: String) throws {
        try withVaultDirectoryAccess {
            let url = try encryptedFileURL(fileName: fileName)
            guard fileManager.fileExists(atPath: url.path) else {
                return
            }

            try fileManager.removeItem(at: url)
        }
    }

    func deleteUnreferencedEncryptedData(keeping referencedFileNames: Set<String>) throws {
        try withVaultDirectoryAccess {
            let encryptedDirectory = try encryptedFilesDirectory()
            guard fileManager.fileExists(atPath: encryptedDirectory.path) else {
                return
            }

            let encryptedFiles = try fileManager.contentsOfDirectory(
                at: encryptedDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            for fileURL in encryptedFiles where fileURL.pathExtension == "mmh" {
                guard !referencedFileNames.contains(fileURL.lastPathComponent) else {
                    continue
                }

                try fileManager.removeItem(at: fileURL)
            }
        }
    }

    func loadEncryptedData(fileName: String) throws -> Data {
        try withVaultDirectoryAccess {
            try Data(contentsOf: encryptedFileURL(fileName: fileName))
        }
    }

    private func ensureVaultDirectories() throws {
        let root = try vaultRootDirectory()
        let encrypted = try encryptedFilesDirectory()

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: encrypted, withIntermediateDirectories: true)
    }

    private func metadataURL() throws -> URL {
        try vaultRootDirectory().appendingPathComponent(metadataFileName)
    }

    private func encryptedFilesDirectory() throws -> URL {
        try vaultRootDirectory().appendingPathComponent(encryptedFolderName, isDirectory: true)
    }

    private func vaultRootDirectory() throws -> URL {
        if let bookmarkData = UserDefaults.standard.data(forKey: vaultBookmarkKey) {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                try? configureVaultDirectory(url)
            }
            return url
        }

        if let path = UserDefaults.standard.string(forKey: vaultPathKey) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw VaultStorageServiceError.applicationSupportDirectoryUnavailable
        }

        return applicationSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    private func withVaultDirectoryAccess<T>(_ action: () throws -> T) throws -> T {
        let url = try vaultRootDirectory()
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try action()
    }
}

// Metadata v3: the file stays JSON for format detection, but vault details
// including item names, folder names, and timestamps are encrypted with the unlocked vault key.
private nonisolated struct EncryptedVaultMetadata: Codable {
    let version: Int
    let encryptedItems: Data?
    let encryptedVault: Data?

    init(version: Int = 3, encryptedItems: Data? = nil, encryptedVault: Data? = nil) {
        self.version = version
        self.encryptedItems = encryptedItems
        self.encryptedVault = encryptedVault
    }
}
