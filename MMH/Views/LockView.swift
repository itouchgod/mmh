//
//  LockView.swift
//  MMH
//
//  Password setup and unlock screen.
//

import AppKit
import SwiftUI

struct LockView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppLanguage.system.rawValue

    @State private var password = ""
    @State private var confirmation = ""
    @State private var dialRotation = Angle.degrees(0)
    @FocusState private var focusedField: LockField?

    var body: some View {
        VStack(spacing: 0) {
            lockHeader

            Divider()
                .overlay(Color.white.opacity(0.08))

            VStack(spacing: authViewModel.hasMasterPassword ? 26 : 14) {
                SafeDialView()
                    .rotationEffect(dialRotation)
                    .animation(.interpolatingSpring(stiffness: 140, damping: 18), value: dialRotation)
                    .frame(width: 270, height: 270)
                    .padding(.top, 16)

                VStack(spacing: 12) {
                    if !authViewModel.hasMasterPassword {
                        vaultDirectoryPicker
                    }

                    passwordInputRow(
                        text: $password,
                        prompt: L10n.text("masterPassword"),
                        field: .password,
                        showsSubmitButton: authViewModel.hasMasterPassword
                    )

                    if !authViewModel.hasMasterPassword {
                        passwordInputRow(
                            text: $confirmation,
                            prompt: L10n.text("confirmPassword"),
                            field: .confirmation,
                            showsSubmitButton: true
                        )
                    }

                    if let message = authViewModel.errorMessage {
                        Text(message)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.44, blue: 0.40))
                            .frame(width: 236, alignment: .leading)
                            .lineLimit(2)
                    }
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(lockBackground)
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: 360, height: authViewModel.hasMasterPassword ? 400 : 490)
        .onAppear {
            focusedField = .password
        }
        .onChange(of: password) { oldValue, newValue in
            spinDialIfNeeded(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: confirmation) { oldValue, newValue in
            spinDialIfNeeded(oldValue: oldValue, newValue: newValue)
        }
    }

    private var lockHeader: some View {
        HStack {
            Spacer()
                .frame(width: 88)

            Spacer()

            Text("MMH")
                .font(.system(size: 19, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.66))
                .tracking(4)

            Spacer()

            Spacer()
                .frame(width: 88)
        }
        .frame(height: 34)
    }

    private var vaultDirectoryPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                chooseVaultDirectory()
            } label: {
                Label(L10n.text("chooseEncryptedStorage"), systemImage: "externaldrive.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.78))

            Text(authViewModel.vaultDirectoryPath ?? L10n.text("encryptedStorageHint"))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 236, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.black.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        }
    }

    private func passwordInputRow(
        text: Binding<String>,
        prompt: String,
        field: LockField,
        showsSubmitButton: Bool
    ) -> some View {
        HStack(spacing: 8) {
            SecureField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.86))
                .focused($focusedField, equals: field)
                .onSubmit(submit)

            if showsSubmitButton {
                Button(action: submit) {
                    if authViewModel.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSubmit ? Color.white.opacity(0.64) : Color.white.opacity(0.30))
                .disabled(!canSubmit)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(width: 236, height: 32)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.black.opacity(0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(focusedField == field ? 0.34 : 0.18), lineWidth: 3)
                )
        }
    }

    private var canSubmit: Bool {
        if authViewModel.isProcessing || authViewModel.isRetryDelayActive {
            return false
        }

        if authViewModel.hasMasterPassword {
            return !password.isEmpty
        }

        return !password.isEmpty && !confirmation.isEmpty && authViewModel.vaultDirectoryPath != nil
    }

    private func submit() {
        if authViewModel.hasMasterPassword {
            authViewModel.unlock(password: password)
        } else {
            authViewModel.createMasterPassword(password, confirmation: confirmation)
        }

        if authViewModel.isUnlocked {
            password = ""
            confirmation = ""
        }
    }

    private func spinDialIfNeeded(oldValue: String, newValue: String) {
        guard newValue.count > oldValue.count else {
            return
        }

        let direction = Bool.random() ? 1.0 : -1.0
        let degrees = Double.random(in: 28...92) * direction
        dialRotation += .degrees(degrees)
    }

    private func chooseVaultDirectory() {
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

        authViewModel.chooseVaultDirectory(url)
    }

    private var lockBackground: Color {
        Color(red: 0.17, green: 0.17, blue: 0.18)
    }
}

private enum LockField {
    case password
    case confirmation
}

private struct SafeDialView: View {
    private let tickCount = 120
    private let labels = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size * 0.49
            let tickOuterRadius = radius * 0.94
            let labelRadius = radius * 0.70
            let labelSize = size * 0.084

            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: size * 0.99, height: size * 0.99)
                    .position(center)

                ForEach(0..<tickCount, id: \.self) { index in
                    let isMajor = index % 10 == 0
                    let angle = Angle.degrees(Double(index) * 360.0 / Double(tickCount) - 90)
                    let length = isMajor ? size * 0.060 : size * 0.043

                    Capsule()
                        .fill(Color.white.opacity(isMajor ? 0.78 : 0.62))
                        .frame(width: isMajor ? 1.7 : 1.2, height: length)
                        .position(point(on: center, radius: tickOuterRadius - length / 2, angle: angle))
                        .rotationEffect(angle)
                }

                ForEach(Array(labels.enumerated()), id: \.offset) { pair in
                    let index = pair.offset
                    let value = pair.element
                    let angle = Angle.degrees(Double(index) * 36.0 - 90.0)

                    Text("\(value)")
                        .font(.system(size: labelSize, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .rotationEffect(angle + .degrees(90))
                        .position(point(on: center, radius: labelRadius, angle: angle))
                }

                Circle()
                    .fill(Color(red: 0.18, green: 0.18, blue: 0.19))
                    .frame(width: size * 0.40, height: size * 0.40)
                    .shadow(color: Color.black.opacity(0.24), radius: 10, y: 2)
                    .position(center)
            }
        }
        .accessibilityHidden(true)
    }

    private func point(on center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(cos(angle.radians)) * radius,
            y: center.y + CGFloat(sin(angle.radians)) * radius
        )
    }
}

struct LockView_Previews: PreviewProvider {
    static var previews: some View {
        LockView()
            .environmentObject(AuthViewModel())
    }
}
