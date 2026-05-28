//
//  AuthViewModel.swift
//  MMH
//
//  Owns lock state and master password setup/verification.
//

import Foundation
import Combine
import CryptoKit

enum AuthViewModelError: LocalizedError {
    case passwordTooShort
    case passwordMismatch
    case missingVaultPassword

    var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            return L10n.text("passwordTooShort")
        case .passwordMismatch:
            return L10n.text("passwordMismatch")
        case .missingVaultPassword:
            return L10n.text("missingVaultPassword")
        }
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var hasMasterPassword: Bool
    @Published private(set) var isUnlocked = false
    @Published private(set) var isProcessing = false
    @Published private(set) var isRetryDelayActive = false
    @Published private(set) var vaultDirectoryPath: String?
    @Published var errorMessage: String?

    private let keychainService: any KeychainServicing
    private let cryptoService: CryptoService
    private let storageService: VaultStorageService
    private var encryptionKey: SymmetricKey?
    private var failedUnlockAttempts = 0

    init(
        keychainService: any KeychainServicing = KeychainService(),
        cryptoService: CryptoService = CryptoService(),
        storageService: VaultStorageService = VaultStorageService()
    ) {
        self.keychainService = keychainService
        self.cryptoService = cryptoService
        self.storageService = storageService
        self.hasMasterPassword = keychainService.hasMasterPassword()
        self.vaultDirectoryPath = storageService.hasConfiguredVaultDirectory()
            ? (try? storageService.vaultDirectoryURL().path)
            : nil
    }

    func verifyMasterPassword(_ password: String) -> Bool {
        do {
            guard
                let salt = try keychainService.read(.passwordSalt),
                let verifier = try keychainService.read(.passwordVerifier)
            else {
                return false
            }

            return try cryptoService.verify(password: password, salt: salt, expectedVerifier: verifier)
        } catch {
            return false
        }
    }

    func makePendingMasterPassword(password: String, confirmation: String) throws -> PendingMasterPassword {
        guard password.count >= 8 else {
            throw AuthViewModelError.passwordTooShort
        }

        guard password == confirmation else {
            throw AuthViewModelError.passwordMismatch
        }

        let salt = cryptoService.makeSalt()
        let verifier = try cryptoService.makePasswordVerifier(password: password, salt: salt)
        let key = try cryptoService.deriveKey(password: password, salt: salt)
        return PendingMasterPassword(salt: salt, verifier: verifier, key: key)
    }

    func commitMasterPasswordChange(_ pendingPassword: PendingMasterPassword) throws {
        try keychainService.save(pendingPassword.salt, account: .passwordSalt)
        try keychainService.save(pendingPassword.verifier, account: .passwordVerifier)
        encryptionKey = pendingPassword.key
        failedUnlockAttempts = 0
        errorMessage = nil
    }

    func createMasterPassword(_ password: String, confirmation: String) {
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        guard storageService.hasConfiguredVaultDirectory() else {
            errorMessage = L10n.text("chooseEncryptedStorageError")
            return
        }

        guard password.count >= 8 else {
            errorMessage = L10n.text("passwordTooShort")
            return
        }

        guard password == confirmation else {
            errorMessage = L10n.text("passwordMismatch")
            return
        }

        do {
            let pendingPassword = try makePendingMasterPassword(
                password: password,
                confirmation: confirmation
            )

            try keychainService.save(pendingPassword.salt, account: .passwordSalt)
            try keychainService.save(pendingPassword.verifier, account: .passwordVerifier)

            encryptionKey = pendingPassword.key
            hasMasterPassword = true
            isUnlocked = true
            failedUnlockAttempts = 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseVaultDirectory(_ url: URL) {
        do {
            try storageService.configureVaultDirectory(url)
            vaultDirectoryPath = url.standardizedFileURL.path
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unlock(password: String) {
        errorMessage = nil

        guard !isRetryDelayActive else {
            errorMessage = L10n.text("pleaseWait")
            return
        }

        guard !password.isEmpty else {
            errorMessage = L10n.text("enterMasterPassword")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            guard
                let salt = try keychainService.read(.passwordSalt),
                let verifier = try keychainService.read(.passwordVerifier)
            else {
                hasMasterPassword = false
                errorMessage = L10n.text("missingVaultPassword")
                return
            }

            if try cryptoService.verify(password: password, salt: salt, expectedVerifier: verifier) {
                encryptionKey = try cryptoService.deriveKey(password: password, salt: salt)
                isUnlocked = true
                failedUnlockAttempts = 0
            } else {
                handleWrongPassword()
            }
        } catch {
            handleWrongPassword()
        }
    }

    func lock() {
        isUnlocked = false
        encryptionKey = nil
        errorMessage = nil
    }

    func currentEncryptionKey() -> SymmetricKey? {
        encryptionKey
    }

    private func handleWrongPassword() {
        failedUnlockAttempts += 1
        errorMessage = L10n.text("wrongPassword")

        if failedUnlockAttempts >= 5 {
            isRetryDelayActive = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                isRetryDelayActive = false
                failedUnlockAttempts = 0
            }
        }
    }
}

nonisolated struct PendingMasterPassword {
    let salt: Data
    let verifier: Data
    let key: SymmetricKey
}
