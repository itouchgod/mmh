//
//  FilePreviewView.swift
//  MMH
//
//  Displays a temporary decrypted image or video file.
//

import AVKit
import SwiftUI

struct FilePreviewView: View {
    let preview: VaultPreview

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppLanguage.system.rawValue
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.item.originalFileName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(preview.item.fileType.displayName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.text("close")) {
                    dismiss()
                }
            }
            .padding()

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.92))
        }
        .frame(minWidth: 760, minHeight: 520)
        .onDisappear {
            stopVideo()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch preview.item.fileType {
        case .image:
            imagePreview
        case .video:
            videoPreview
        case .unknown:
            unsupportedPreview
        }
    }

    private var imagePreview: some View {
        Group {
            if let image = NSImage(contentsOf: preview.fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                unsupportedPreview
            }
        }
    }

    private var videoPreview: some View {
        VideoPlayer(player: player)
            .padding()
            .onAppear {
                if player == nil {
                    player = AVPlayer(url: preview.fileURL)
                }
            }
            .onDisappear {
                stopVideo()
            }
    }

    private var unsupportedPreview: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text(L10n.text("previewUnavailable"))
                .font(.headline)
        }
        .foregroundStyle(.white)
    }

    private func stopVideo() {
        player?.pause()
        player = nil
    }
}
