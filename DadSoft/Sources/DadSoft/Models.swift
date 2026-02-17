import Foundation

// MARK: - App Screen (Hub Navigation)

enum AppScreen: Equatable {
    case hub
    case remoteControl
    case windowsInstaller
}

// MARK: - Installation Steps (Windows Installer)

enum InstallStep: Int, CaseIterable, Identifiable {
    case systemCheck
    case installPrereqs
    case downloadWindows
    case createVM
    case installWindows
    case complete

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .systemCheck:    return "System Check"
        case .installPrereqs: return "Software"
        case .downloadWindows: return "Windows"
        case .createVM:       return "Create VM"
        case .installWindows: return "Install"
        case .complete:       return "Done"
        }
    }

    var description: String {
        switch self {
        case .systemCheck:    return "Check compatibility"
        case .installPrereqs: return "Install required software"
        case .downloadWindows: return "Download Windows 11"
        case .createVM:       return "Create virtual machine"
        case .installWindows: return "Install Windows 11"
        case .complete:       return "All done!"
        }
    }
}

// MARK: - Remote Control Steps

enum RemoteControlStep: Int, CaseIterable, Identifiable {
    case installAnyDesk
    case permissions
    case unattendedAccess
    case share

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .installAnyDesk:   return "Install AnyDesk"
        case .permissions:      return "Permissions"
        case .unattendedAccess: return "Unattended Access"
        case .share:            return "Share Address"
        }
    }

    var description: String {
        switch self {
        case .installAnyDesk:   return "Install remote control software"
        case .permissions:      return "Grant screen and input access"
        case .unattendedAccess: return "Set up unattended access"
        case .share:            return "Share your AnyDesk address"
        }
    }
}

// MARK: - Remote Control Info

struct RemoteControlInfo {
    var anyDeskInstalled: Bool = false
    var anyDeskAddress: String = ""
    var screenRecordingGranted: Bool = false
    var accessibilityGranted: Bool = false
    var unattendedAccessSet: Bool = false
}

// MARK: - Step Status

enum StepStatus: Equatable {
    case pending
    case active
    case completed
    case failed(String)

    var icon: String {
        switch self {
        case .pending:   return "circle"
        case .active:    return "arrow.right.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }
}

// MARK: - System Info

struct SystemInfo {
    var macOSVersion: String = ""
    var chipName: String = ""
    var ramGB: Int = 0
    var freeSpaceGB: Int = 0
    var isConnected: Bool = false
    var allPassed: Bool = false

    var vmRAM: Int {
        if ramGB <= 8 { return 2048 }
        if ramGB <= 16 { return 4096 }
        return 8192
    }

    var vmCores: Int {
        if ramGB <= 8 { return 2 }
        if ramGB <= 16 { return 4 }
        return 6
    }
}

// MARK: - Prereq Status

struct PrereqStatus: Identifiable {
    let id = UUID()
    let name: String
    var installed: Bool
    var installing: Bool = false
    var failed: Bool = false
}

// MARK: - Uninstall Item

struct UninstallItem: Identifiable {
    let id: String
    let name: String
    let detail: String
    var sizeBytes: Int64
    var exists: Bool
    var selected: Bool = true
    var deleting: Bool = false
    var deleted: Bool = false
    var failed: Bool = false

    var sizeString: String { formatBytes(sizeBytes) }
}

// MARK: - Contact Result

struct ContactResult: Identifiable {
    let id = UUID()
    let name: String
    let phone: String
    let phoneLabel: String
}

// MARK: - VM Config

struct VMConfig {
    static let name = "Windows 11"
    static let diskSizeGB = 64
    static let downloadDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/Windows11-VM-Setup")
    static let spiceToolsURL = "https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe"
}
