//
//  VaultItem.swift
//  MMH
//
//  Lightweight JSON metadata for one encrypted vault file.
//

import Foundation

nonisolated enum VaultFileType: String, Codable, CaseIterable {
    case image
    case video
    case unknown

    var displayName: String {
        switch self {
        case .image:
            return "Image"
        case .video:
            return "Video"
        case .unknown:
            return "File"
        }
    }
}

nonisolated struct VaultItem: Identifiable, Codable, Equatable {
    let id: UUID
    let originalFileName: String
    let encryptedFileName: String
    let fileType: VaultFileType
    let importedAt: Date
    let originalExtension: String
    let encryptedFileSize: Int64?
    let contentHash: String?
    let folderID: UUID?

    init(
        id: UUID = UUID(),
        originalFileName: String,
        encryptedFileName: String,
        fileType: VaultFileType,
        importedAt: Date = Date(),
        originalExtension: String,
        encryptedFileSize: Int64? = nil,
        contentHash: String? = nil,
        folderID: UUID? = nil
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.encryptedFileName = encryptedFileName
        self.fileType = fileType
        self.importedAt = importedAt
        self.originalExtension = originalExtension
        self.encryptedFileSize = encryptedFileSize
        self.contentHash = contentHash
        self.folderID = folderID
    }

    func moved(to folderID: UUID?) -> VaultItem {
        VaultItem(
            id: id,
            originalFileName: originalFileName,
            encryptedFileName: encryptedFileName,
            fileType: fileType,
            importedAt: importedAt,
            originalExtension: originalExtension,
            encryptedFileSize: encryptedFileSize,
            contentHash: contentHash,
            folderID: folderID
        )
    }
}

nonisolated struct VaultFolder: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let directoryPaths: [String]
    let decryptedFolderPath: String?
    let decryptedParentBookmarkData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        directoryPaths: [String] = [],
        decryptedFolderPath: String? = nil,
        decryptedParentBookmarkData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.directoryPaths = directoryPaths
        self.decryptedFolderPath = decryptedFolderPath
        self.decryptedParentBookmarkData = decryptedParentBookmarkData
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case directoryPaths
        case decryptedFolderPath
        case decryptedParentBookmarkData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        directoryPaths = try container.decodeIfPresent([String].self, forKey: .directoryPaths) ?? []
        decryptedFolderPath = try container.decodeIfPresent(String.self, forKey: .decryptedFolderPath)
        decryptedParentBookmarkData = try container.decodeIfPresent(Data.self, forKey: .decryptedParentBookmarkData)
    }

    func updated(
        directoryPaths: [String]? = nil,
        decryptedFolderPath: String? = nil,
        decryptedParentBookmarkData: Data? = nil
    ) -> VaultFolder {
        VaultFolder(
            id: id,
            name: name,
            createdAt: createdAt,
            directoryPaths: directoryPaths ?? self.directoryPaths,
            decryptedFolderPath: decryptedFolderPath ?? self.decryptedFolderPath,
            decryptedParentBookmarkData: decryptedParentBookmarkData ?? self.decryptedParentBookmarkData
        )
    }
}

nonisolated struct VaultMetadata: Codable, Equatable {
    var items: [VaultItem]
    var folders: [VaultFolder]

    init(items: [VaultItem] = [], folders: [VaultFolder] = []) {
        self.items = items
        self.folders = folders
    }
}
