//
//  CryptoService.swift
//  MMH
//
//  Handles password-based key derivation and verification helpers.
//

import CryptoKit
import Foundation
import Security

enum CryptoServiceError: LocalizedError {
    case invalidPasswordEncoding
    case missingCombinedSealedBox

    var errorDescription: String? {
        switch self {
        case .invalidPasswordEncoding:
            return "Unable to read the password."
        case .missingCombinedSealedBox:
            return "Unable to package encrypted data."
        }
    }
}

nonisolated struct CryptoService {
    private let verifierMessage = Data("MMH.PasswordVerifier.v1".utf8)
    private let keyInfo = Data("MMH.MasterKey.v1".utf8)

    func makeSalt(byteCount: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes)
    }

    func makePasswordVerifier(password: String, salt: Data) throws -> Data {
        let key = try deriveKey(password: password, salt: salt)
        let code = HMAC<SHA256>.authenticationCode(for: verifierMessage, using: key)
        return Data(code)
    }

    func verify(password: String, salt: Data, expectedVerifier: Data) throws -> Bool {
        let candidate = try makePasswordVerifier(password: password, salt: salt)
        return candidate.withUnsafeBytes { candidateBytes in
            expectedVerifier.withUnsafeBytes { expectedBytes in
                guard candidateBytes.count == expectedBytes.count else {
                    return false
                }

                var difference: UInt8 = 0
                for index in 0..<candidateBytes.count {
                    difference |= candidateBytes[index] ^ expectedBytes[index]
                }
                return difference == 0
            }
        }
    }

    func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw CryptoServiceError.invalidPasswordEncoding
        }

        let inputKey = SymmetricKey(data: passwordData)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: keyInfo,
            outputByteCount: 32
        )
    }

    func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw CryptoServiceError.missingCombinedSealedBox
        }

        return combined
    }

    func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
}
