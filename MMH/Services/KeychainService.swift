//
//  KeychainService.swift
//  MMH
//
//  Stores small authentication secrets in the macOS Keychain.
//

import Foundation
import Security

protocol KeychainServicing {
    func read(_ account: KeychainService.Account) throws -> Data?
    func save(_ data: Data, account: KeychainService.Account) throws
    func delete(_ account: KeychainService.Account) throws
    func hasMasterPassword() -> Bool
}

enum KeychainServiceError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

nonisolated struct KeychainService {
    private let service = "com.ob8.MMH"

    enum Account: String {
        case passwordSalt
        case passwordVerifier
    }

    func read(_ account: Account) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }

        return item as? Data
    }

    func save(_ data: Data, account: Account) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        if status != errSecItemNotFound {
            throw KeychainServiceError.unexpectedStatus(status)
        }

        var newItem = query
        newItem[kSecValueData as String] = data

        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(addStatus)
        }
    }

    func delete(_ account: Account) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    func hasMasterPassword() -> Bool {
        do {
            let salt = try read(.passwordSalt)
            let verifier = try read(.passwordVerifier)
            return salt != nil && verifier != nil
        } catch {
            return false
        }
    }
}

extension KeychainService: KeychainServicing {}
