//
//  Localization.swift
//  MMH
//
//  Lightweight in-app language switching.
//

import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case chinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System / 跟随系统"
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }
}

nonisolated enum L10n {
    static func text(_ key: String) -> String {
        let language = activeLanguage()
        return translations[key]?[language] ?? translations[key]?[.english] ?? key
    }

    static func format(_ key: String, _ values: CVarArg...) -> String {
        String(format: text(key), arguments: values)
    }

    private static func activeLanguage() -> AppLanguage {
        let stored = UserDefaults.standard.string(forKey: AppPreferenceKeys.appLanguage)
        let preference = AppLanguage(rawValue: stored ?? "") ?? .system
        if preference != .system {
            return preference
        }

        let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferredLanguage.hasPrefix("zh") ? .chinese : .english
    }

    private static let translations: [String: [AppLanguage: String]] = [
        "unlockVault": [.english: "Unlock Vault", .chinese: "解锁保险库"],
        "setMasterPassword": [.english: "Set Master Password", .chinese: "设置主密码"],
        "masterPassword": [.english: "Master password", .chinese: "主密码"],
        "confirmPassword": [.english: "Confirm password", .chinese: "确认密码"],
        "unlock": [.english: "Unlock", .chinese: "解锁"],
        "createVault": [.english: "Create Vault", .chinese: "创建保险库"],
        "localSafetyNote": [.english: "All files stay on this Mac. The master password is never stored as plain text.", .chinese: "所有文件都保存在这台 Mac 上。主密码不会以明文保存。"],
        "chooseEncryptedStorage": [.english: "Choose encrypted storage...", .chinese: "选择加密存储目录..."],
        "encryptedStorageHint": [.english: "Encrypted files will be stored in the folder you choose.", .chinese: "加密文件会保存在你选择的文件夹中。"],
        "useFolder": [.english: "Use Folder", .chinese: "使用文件夹"],
        "chooseStorageMessage": [.english: "Choose where MMH should store encrypted data.", .chinese: "请选择 MMH 存放加密数据的位置。"],

        "mmhVault": [.english: "MMH Vault", .chinese: "MMH 保险库"],
        "mainSubtitle": [.english: "Encrypt whole folders locally, then restore them in your MMH storage folder.", .chinese: "在本机加密整个文件夹，并在 MMH 存储目录中恢复。"],
        "encryptFolder": [.english: "Encrypt Folder...", .chinese: "加密文件夹..."],
        "changePassword": [.english: "Change Password...", .chinese: "修改密码..."],
        "settings": [.english: "Settings", .chinese: "设置"],
        "lock": [.english: "Lock", .chinese: "锁定"],
        "dropFolderHere": [.english: "Drop a folder here", .chinese: "将文件夹拖到这里"],
        "encryptingFolder": [.english: "Encrypting folder...", .chinese: "正在加密文件夹..."],
        "dropZoneHelp": [.english: "MMH stores encrypted data in your chosen storage folder and restores decrypted folders there.", .chinese: "MMH 会把加密数据和解密后的文件夹都放在你选择的存储目录中。"],
        "encryptedFolders": [.english: "Encrypted Folders", .chinese: "已加密文件夹"],
        "decrypt": [.english: "Decrypt...", .chinese: "解密..."],
        "deleteEncryptedFolder": [.english: "Delete Encrypted Folder...", .chinese: "删除加密文件夹..."],
        "noEncryptedFolders": [.english: "No encrypted folders yet", .chinese: "还没有加密文件夹"],
        "chooseOrDragFolder": [.english: "Choose a folder or drag one in.", .chinese: "请选择或拖入一个文件夹。"],
        "filesCount": [.english: "%d files", .chinese: "%d 个文件"],
        "encryptedDate": [.english: "Encrypted %@", .chinese: "加密于 %@"],
        "files": [.english: "Files", .chinese: "文件"],
        "subfolders": [.english: "Subfolders", .chinese: "子文件夹"],
        "encryptedSize": [.english: "Encrypted Size", .chinese: "加密大小"],
        "decrypted": [.english: "Decrypted", .chinese: "已解密"],
        "encrypted": [.english: "Encrypted", .chinese: "已加密"],
        "selectEncryptedFolder": [.english: "Select an encrypted folder", .chinese: "选择一个加密文件夹"],
        "folderActionsHere": [.english: "Folder-level actions appear here.", .chinese: "文件夹级操作会显示在这里。"],
        "delete": [.english: "Delete", .chinese: "删除"],
        "cancel": [.english: "Cancel", .chinese: "取消"],
        "encrypt": [.english: "Encrypt", .chinese: "加密"],
        "deleteEncryptedCopyMessage": [.english: "This removes the encrypted copy from MMH. Your original external folder is not touched.", .chinese: "这会从 MMH 删除加密副本，不会影响原外部文件夹。"],
        "deleteFolderTitle": [.english: "Delete %@?", .chinese: "删除 %@？"],
        "thisEncryptedFolder": [.english: "this encrypted folder", .chinese: "这个加密文件夹"],
        "decryptedAt": [.english: "Decrypted at %@. Turn the switch off to encrypt it again and permanently delete the visible folder.", .chinese: "已解密到 %@。关闭开关会重新加密，并永久删除可见的明文文件夹。"],
        "restoreToPath": [.english: "Encrypted. Turning the switch on restores it to %@.", .chinese: "已加密。打开开关会恢复到 %@。"],
        "restoreToStorage": [.english: "Encrypted. Turning the switch on restores it in your MMH storage folder.", .chinese: "已加密。打开开关会恢复到 MMH 存储目录。"],
        "lockHider": [.english: "Lock Hider", .chinese: "锁定隐藏器"],
        "primaryVault": [.english: "Primary Vault", .chinese: "主保险库"],
        "allFiles": [.english: "All Files", .chinese: "全部文件"],
        "secureNotes": [.english: "Secure Notes", .chinese: "安全笔记"],
        "allNotes": [.english: "All Notes", .chinese: "全部笔记"],
        "notesComingSoon": [.english: "Secure notes are coming in a later update.", .chinese: "安全笔记会在后续版本中加入。"],
        "sortBy": [.english: "Sort by", .chinese: "排序"],
        "sortName": [.english: "Name", .chinese: "名称"],
        "sortDateAdded": [.english: "Date Added", .chinese: "添加日期"],
        "sortVisibility": [.english: "Visibility", .chinese: "可见状态"],
        "announcement": [.english: "Announcement", .chinese: "公告"],
        "announcementMessage": [.english: "Drag a folder into the vault or use + to encrypt it.", .chinese: "可将文件夹拖入保险库，或点击 + 进行加密。"],
        "folderRowSubtitle": [.english: "%@, encrypted and moved to vault.", .chinese: "%@，已加密并移入保险库。"],
        "visible": [.english: "Visible", .chinese: "可见"],
        "hidden": [.english: "Hidden", .chinese: "隐藏"],
        "openInFinder": [.english: "Open in Finder", .chinese: "在访达中打开"],
        "unhideAll": [.english: "Unhide All", .chinese: "全部显示"],
        "unhideAllItems": [.english: "Unhide All Items", .chinese: "显示全部项目"],
        "hideSelectedItems": [.english: "Hide Selected Items", .chinese: "隐藏选中项目"],
        "unhideSelectedItems": [.english: "Unhide Selected Items", .chinese: "显示选中项目"],
        "removeSelectedItems": [.english: "Remove Selected Items", .chinese: "移除选中项目"],
        "noSearchResults": [.english: "No matching folders", .chinese: "没有匹配的文件夹"],
        "tryAnotherSearch": [.english: "Try a different search term.", .chinese: "换个关键词试试。"],

        "preferences": [.english: "Preferences", .chinese: "偏好设置"],
        "general": [.english: "General", .chinese: "通用"],
        "security": [.english: "Security", .chinese: "安全"],
        "storage": [.english: "Storage", .chinese: "存储"],
        "language": [.english: "Language", .chinese: "语言"],
        "lockWhenInactive": [.english: "Lock MMH when the app is inactive", .chinese: "App 不活跃时锁定 MMH"],
        "lockWhenInactiveHelp": [.english: "Choose how long MMH waits before returning to the password screen after you switch away from the app or the window loses focus.", .chinese: "选择切换到其他 App 或窗口失去焦点后，MMH 多久退回密码登录界面。"],
        "autoLockNever": [.english: "Never", .chinese: "永不"],
        "autoLockAfter30Seconds": [.english: "After 30 seconds", .chinese: "30 秒后"],
        "autoLockAfter1Minute": [.english: "After 1 minute", .chinese: "1 分钟后"],
        "autoLockAfter5Minutes": [.english: "After 5 minutes", .chinese: "5 分钟后"],
        "autoLockAfter15Minutes": [.english: "After 15 minutes", .chinese: "15 分钟后"],
        "showInFinder": [.english: "Show restored folder in Finder after decrypting", .chinese: "解密后在 Finder 中显示恢复的文件夹"],
        "showInFinderHelp": [.english: "Turn this off if you prefer MMH to restore the folder quietly inside your storage location.", .chinese: "如果你希望 MMH 静默恢复文件夹，可关闭此选项。"],
        "plainFoldersTrash": [.english: "Plain folders are permanently deleted after encryption", .chinese: "加密后永久删除明文文件夹"],
        "plainFoldersTrashHelp": [.english: "MMH keeps only the encrypted package. After encryption succeeds, the visible plain folder is deleted directly instead of being moved to Trash.", .chinese: "MMH 只保留加密包。加密成功后，可见的明文文件夹会被直接删除，不再进入废纸篓。"],
        "masterPasswordTitle": [.english: "Master password", .chinese: "主密码"],
        "masterPasswordHelp": [.english: "Change the master password here. Existing encrypted packages are re-encrypted with the new key.", .chinese: "可在这里修改主密码。已有加密包会用新密钥重新加密。"],
        "encryptedStorageLocation": [.english: "Encrypted storage location", .chinese: "加密存储位置"],
        "storageHelp": [.english: "MMH stores encrypted `.mmh` packages and encrypted metadata in this folder. Restored folders appear here too.", .chinese: "MMH 会把 `.mmh` 加密包和加密元数据保存在这里。恢复后的文件夹也会出现在这里。"],
        "noStorageFolder": [.english: "No storage folder selected", .chinese: "尚未选择存储文件夹"],
        "change": [.english: "Change...", .chinese: "更改..."],
        "storageUpdated": [.english: "Storage location updated.", .chinese: "存储位置已更新。"],

        "changeMasterPassword": [.english: "Change Master Password", .chinese: "修改主密码"],
        "currentPassword": [.english: "Current password", .chinese: "当前密码"],
        "newPassword": [.english: "New password", .chinese: "新密码"],
        "confirmNewPassword": [.english: "Confirm new password", .chinese: "确认新密码"],
        "wrongPassword": [.english: "Wrong password.", .chinese: "密码错误。"],
        "vaultLocked": [.english: "Vault is locked.", .chinese: "保险库已锁定。"],
        "close": [.english: "Close", .chinese: "关闭"],
        "previewUnavailable": [.english: "Preview is unavailable.", .chinese: "无法预览。"],

        "passwordTooShort": [.english: "Password must be at least 8 characters.", .chinese: "密码至少需要 8 个字符。"],
        "passwordMismatch": [.english: "Passwords do not match.", .chinese: "两次输入的密码不一致。"],
        "missingVaultPassword": [.english: "No vault password was found.", .chinese: "未找到保险库密码。"],
        "chooseEncryptedStorageError": [.english: "Choose where encrypted files should be stored.", .chinese: "请选择加密文件的存储位置。"],
        "pleaseWait": [.english: "Please wait before trying again.", .chinese: "请稍等后再试。"],
        "enterMasterPassword": [.english: "Enter your master password.", .chinese: "请输入主密码。"],
        "scanningFolder": [.english: "Scanning folder...", .chinese: "正在扫描文件夹..."],
        "encryptingFolderProgress": [.english: "Encrypting folder %d/%d", .chinese: "正在加密文件夹 %d/%d"],
        "encryptingFilesProgress": [.english: "Encrypting files %d/%d", .chinese: "正在加密文件 %d/%d"],
        "decryptingFilesProgress": [.english: "Decrypting files %d/%d", .chinese: "正在解密文件 %d/%d"],
        "encryptedFoldersCount": [.english: "Encrypted %d folder(s).", .chinese: "已加密 %d 个文件夹。"],
        "skippedFoldersCount": [.english: "Skipped %d folder(s).", .chinese: "已跳过 %d 个文件夹。"],
        "noFoldersEncrypted": [.english: "No folders were encrypted.", .chinese: "没有文件夹被加密。"],
        "encryptedButDeleteFailed": [.english: "Encrypted, but the original folder could not be deleted: %@", .chinese: "已加密，但无法删除原文件夹：%@"],
        "deletedEncryptedFolder": [.english: "Deleted encrypted folder %@.", .chinese: "已删除加密文件夹 %@。"],
        "noDecryptedFolderLocation": [.english: "No decrypted folder location is saved.", .chinese: "尚未保存解密文件夹的位置。"],
        "folderAlreadyEncrypted": [.english: "%@ is encrypted.", .chinese: "%@ 已加密。"],
        "encryptingNamedFolder": [.english: "Encrypting %@...", .chinese: "正在加密 %@..."],
        "decryptingNamedFolder": [.english: "Decrypting %@...", .chinese: "正在解密 %@..."],
        "encryptedNamedFolder": [.english: "Encrypted %@. The decrypted folder was permanently deleted.", .chinese: "已加密 %@，解密后的明文文件夹已永久删除。"],
        "masterPasswordChanged": [.english: "Master password changed.", .chinese: "主密码已修改。"],
        "preparingVault": [.english: "Preparing vault...", .chinese: "正在准备保险库..."],
        "reencryptingProgress": [.english: "Re-encrypting %d/%d", .chinese: "正在重新加密 %d/%d"],
        "savingVault": [.english: "Saving vault...", .chinese: "正在保存保险库..."],
        "folderRequired": [.english: "Choose a folder to encrypt.", .chinese: "请选择要加密的文件夹。"],
        "folderUnavailable": [.english: "Unable to read this folder.", .chinese: "无法读取这个文件夹。"],
        "folderEnumerationFailed": [.english: "Unable to read every file in this folder: %@", .chinese: "无法读取这个文件夹中的全部文件：%@"],
        "unsupportedFolderItem": [.english: "This folder contains an unsupported item: %@", .chinese: "这个文件夹包含暂不支持的项目：%@"],
        "unsafeFolderPath": [.english: "This folder contains an unsafe path.", .chinese: "这个文件夹包含不安全的路径。"],
        "thumbnailUnavailable": [.english: "Unable to create thumbnail.", .chinese: "无法创建缩略图。"],
        "applicationSupportUnavailable": [.english: "Unable to locate the Application Support directory.", .chinese: "无法找到 Application Support 目录。"],
        "vaultDirectoryUnavailable": [.english: "Choose where encrypted MMH data should be stored.", .chinese: "请选择 MMH 加密数据的存储位置。"],
        "targetContainsVaultData": [.english: "The selected folder already contains MMH vault data.", .chinese: "所选文件夹已经包含 MMH 保险库数据。"],
        "deletedOneFile": [.english: "Deleted %@.", .chinese: "已删除 %@。"],
        "deletedFilesCount": [.english: "Deleted %d files.", .chinese: "已删除 %d 个文件。"]
    ]
}
