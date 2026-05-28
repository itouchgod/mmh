//
//  FileTypeHelper.swift
//  MMH
//
//  Maps dropped file URLs to supported vault media types.
//

import Foundation
import UniformTypeIdentifiers

nonisolated enum FileTypeHelper {
    static func fileType(for url: URL) -> VaultFileType {
        let pathExtension = url.pathExtension.lowercased()

        if let type = UTType(filenameExtension: pathExtension) {
            if type.conforms(to: .image) {
                return .image
            }

            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return .video
            }
        }

        if imageExtensions.contains(pathExtension) {
            return .image
        }

        if videoExtensions.contains(pathExtension) {
            return .video
        }

        return .unknown
    }

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "tif", "tiff", "bmp", "webp"
    ]

    private static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mkv", "webm"
    ]
}
