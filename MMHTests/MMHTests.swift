import CryptoKit
import XCTest
@testable import MMH

final class CryptoServiceTests: XCTestCase {
    func testPasswordVerifierAcceptsCorrectPasswordAndRejectsWrongPassword() throws {
        let service = CryptoService()
        let salt = service.makeSalt()
        let verifier = try service.makePasswordVerifier(password: "correct horse battery staple", salt: salt)

        XCTAssertTrue(try service.verify(
            password: "correct horse battery staple",
            salt: salt,
            expectedVerifier: verifier
        ))
        XCTAssertFalse(try service.verify(
            password: "wrong password",
            salt: salt,
            expectedVerifier: verifier
        ))
    }

    func testEncryptDecryptRoundTrip() throws {
        let service = CryptoService()
        let salt = service.makeSalt()
        let key = try service.deriveKey(password: "round trip password", salt: salt)
        let originalData = Data("private media bytes".utf8)

        let encryptedData = try service.encrypt(originalData, using: key)
        let decryptedData = try service.decrypt(encryptedData, using: key)

        XCTAssertNotEqual(encryptedData, originalData)
        XCTAssertEqual(decryptedData, originalData)
    }
}

@MainActor
final class AuthViewModelTests: XCTestCase {
    func testCreateMasterPasswordUnlocksVault() {
        let viewModel = AuthViewModel(keychainService: MockKeychainService())

        viewModel.createMasterPassword("password123", confirmation: "password123")

        XCTAssertTrue(viewModel.hasMasterPassword)
        XCTAssertTrue(viewModel.isUnlocked)
        XCTAssertNotNil(viewModel.currentEncryptionKey())
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUnlockWithWrongPasswordFails() {
        let keychainService = MockKeychainService()
        let setupViewModel = AuthViewModel(keychainService: keychainService)
        setupViewModel.createMasterPassword("password123", confirmation: "password123")
        setupViewModel.lock()

        let viewModel = AuthViewModel(keychainService: keychainService)
        viewModel.unlock(password: "wrong-password")

        XCTAssertFalse(viewModel.isUnlocked)
        XCTAssertNil(viewModel.currentEncryptionKey())
        XCTAssertEqual(viewModel.errorMessage, "Wrong password.")
    }

    func testLockClearsCurrentEncryptionKey() {
        let viewModel = AuthViewModel(keychainService: MockKeychainService())
        viewModel.createMasterPassword("password123", confirmation: "password123")

        viewModel.lock()

        XCTAssertFalse(viewModel.isUnlocked)
        XCTAssertNil(viewModel.currentEncryptionKey())
    }
}

private final class MockKeychainService: KeychainServicing {
    private var storage: [KeychainService.Account: Data] = [:]

    func read(_ account: KeychainService.Account) throws -> Data? {
        storage[account]
    }

    func save(_ data: Data, account: KeychainService.Account) throws {
        storage[account] = data
    }

    func hasMasterPassword() -> Bool {
        storage[.passwordSalt] != nil && storage[.passwordVerifier] != nil
    }
}
