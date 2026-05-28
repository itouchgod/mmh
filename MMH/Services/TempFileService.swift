//
//  TempFileService.swift
//  MMH
//
//  Writes decrypted preview files and removes them when no longer needed.
//

import Foundation

nonisolated struct TempFileService {
    private let fileManager = FileManager.default
    private let folderName = "MMHPreviews"

    func writePreviewData(_ data: Data, for item: VaultItem) throws -> URL {
        try ensurePreviewDirectory()

        let fileName: String
        if item.originalExtension.isEmpty {
            fileName = item.id.uuidString
        } else {
            fileName = "\(item.id.uuidString).\(item.originalExtension)"
        }

        let url = try previewDirectory().appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        return url
    }

    func cleanup(_ url: URL?) {
        guard let url else {
            return
        }

        try? fileManager.removeItem(at: url)
    }

    func cleanupAll() {
        guard let directory = try? previewDirectory() else {
            return
        }

        try? fileManager.removeItem(at: directory)
    }

    private func ensurePreviewDirectory() throws {
        try fileManager.createDirectory(
            at: try previewDirectory(),
            withIntermediateDirectories: true
        )
    }

    private func previewDirectory() throws -> URL {
        fileManager.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    }
}
