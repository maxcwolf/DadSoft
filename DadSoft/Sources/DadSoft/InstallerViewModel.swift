import Foundation
import SwiftUI
import Contacts

@MainActor
final class InstallerViewModel: ObservableObject {
    // MARK: - Hub Navigation
    @Published var currentScreen: AppScreen = .hub

    // MARK: - Windows Installer State
    @Published var currentStep: InstallStep = .systemCheck
    @Published var stepStatuses: [InstallStep: StepStatus] = {
        var d: [InstallStep: StepStatus] = [:]
        for step in InstallStep.allCases { d[step] = .pending }
        return d
    }()

    @Published var systemInfo = SystemInfo()
    @Published var prereqs: [PrereqStatus] = []
    @Published var logLines: [String] = []

    // Download state
    @Published var downloadProgress: Double = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var downloadStatusText: String = ""
    @Published var isDownloading = false

    // General
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var windowsISOPath: URL?
    @Published var vmPath: URL?

    // Uninstall
    @Published var showUninstall = false
    @Published var uninstallItems: [UninstallItem] = []
    @Published var isUninstalling = false

    // MARK: - Remote Control State
    @Published var currentRemoteStep: RemoteControlStep = .installAnyDesk
    @Published var remoteStepStatuses: [RemoteControlStep: StepStatus] = {
        var d: [RemoteControlStep: StepStatus] = [:]
        for step in RemoteControlStep.allCases { d[step] = .pending }
        return d
    }()
    @Published var remoteControlInfo = RemoteControlInfo()

    // Hub quick-action state
    @Published var anyDeskReady = false
    @Published var windowsVMReady = false

    // Son contact
    @Published var showSonSetup = false
    @Published var sonName: String = ""
    @Published var sonPhone: String = ""
    @Published var contactResults: [ContactResult] = []

    // MARK: - Hub Detection

    func scanInstalledFeatures() {
        let fm = FileManager.default
        anyDeskReady = fm.fileExists(atPath: "/Applications/AnyDesk.app")
        let vmPath = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/\(VMConfig.name).utm").path
        windowsVMReady = fm.fileExists(atPath: vmPath)
    }

    func launchAnyDeskAndShare() {
        Task {
            // Launch AnyDesk
            let _ = await ShellRunner.run("open /Applications/AnyDesk.app")
            // Wait for it to start
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // Try to get the address
            await fetchAnyDeskAddress()
            // Build message
            let address = remoteControlInfo.anyDeskAddress
            let text: String
            if !address.isEmpty {
                text = "Here's my AnyDesk address so you can remote in: \(address)"
            } else {
                text = "I've opened AnyDesk — I'll read you my address from the screen."
            }
            // Send directly to son if configured
            if !sonPhone.isEmpty {
                await sendMessageToSon(text)
            } else {
                let picker = NSSharingServicePicker(items: [text])
                if let window = NSApp.keyWindow,
                   let contentView = window.contentView {
                    picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                }
            }
        }
    }

    func launchWindowsVM() {
        let vmPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/\(VMConfig.name).utm").path
        Task {
            await ShellRunner.run("open \"\(vmPath)\"")
        }
    }

    // MARK: - Hub Navigation

    func navigateTo(_ screen: AppScreen) {
        logLines = []
        errorMessage = nil
        currentScreen = screen

        switch screen {
        case .hub:
            break
        case .windowsInstaller:
            // Start system check if nothing has started yet
            if status(for: .systemCheck) == .pending {
                setStatus(.systemCheck, .active)
                currentStep = .systemCheck
                Task { await runSystemCheck() }
            }
        case .remoteControl:
            // Start first step if nothing has started yet
            if remoteStatus(for: .installAnyDesk) == .pending {
                setRemoteStatus(.installAnyDesk, .active)
                currentRemoteStep = .installAnyDesk
                Task { await runInstallAnyDesk() }
            }
        }
    }

    func returnToHub() {
        currentScreen = .hub
        scanInstalledFeatures()
    }

    // MARK: - Son Contact

    func loadSonContact() {
        sonName = UserDefaults.standard.string(forKey: "sonName") ?? ""
        sonPhone = UserDefaults.standard.string(forKey: "sonPhone") ?? ""
        if sonName.isEmpty {
            showSonSetup = true
        }
    }

    func saveSonContact(name: String, phone: String) {
        sonName = name
        sonPhone = phone
        UserDefaults.standard.set(name, forKey: "sonName")
        UserDefaults.standard.set(phone, forKey: "sonPhone")
        showSonSetup = false
    }

    func searchContacts(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            contactResults = []
            return
        }

        let store = CNContactStore()
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        let predicate = CNContact.predicateForContacts(matchingName: trimmed)
        guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch) else {
            contactResults = []
            return
        }

        var results: [ContactResult] = []
        for contact in contacts {
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !name.isEmpty else { continue }
            for labeled in contact.phoneNumbers {
                let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: labeled.label ?? "")
                results.append(ContactResult(
                    name: name,
                    phone: labeled.value.stringValue,
                    phoneLabel: label.isEmpty ? "Phone" : label
                ))
            }
        }
        contactResults = results
    }

    func sendMessageToSon(_ text: String) async {
        guard !sonPhone.isEmpty else { return }

        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPhone = sonPhone
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Messages"
            send "\(escapedText)" to buddy "\(escapedPhone)" of (1st account whose service type = iMessage)
        end tell
        """

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("dadsoft_msg.applescript")
        try? script.write(to: tempFile, atomically: true, encoding: .utf8)
        let result = await ShellRunner.run("osascript \"\(tempFile.path)\"")
        try? FileManager.default.removeItem(at: tempFile)

        if result.exitCode == 0 {
            statusMessage = "Sent to \(sonName)"
            return
        }

        // Fallback: open Messages to the conversation and copy message to clipboard
        let encoded = sonPhone.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? sonPhone
        let _ = await ShellRunner.run("open 'imessage://\(encoded)'")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "Message copied — paste and send in Messages"
    }

    // MARK: - Windows Step Transitions

    func status(for step: InstallStep) -> StepStatus {
        stepStatuses[step] ?? .pending
    }

    private func setStatus(_ step: InstallStep, _ status: StepStatus) {
        stepStatuses[step] = status
    }

    private func advance(from step: InstallStep) {
        setStatus(step, .completed)
        if let nextIndex = InstallStep.allCases.firstIndex(of: step).map({ $0 + 1 }),
           nextIndex < InstallStep.allCases.count {
            let next = InstallStep.allCases[nextIndex]
            currentStep = next
            setStatus(next, .active)
        }
    }

    private func fail(_ step: InstallStep, _ message: String) {
        setStatus(step, .failed(message))
        errorMessage = message
        isBusy = false
        statusMessage = "Error"
    }

    private func appendLog(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logLines.append(trimmed)
        if logLines.count > 200 { logLines.removeFirst() }
    }

    // MARK: - Remote Control Step Transitions

    func remoteStatus(for step: RemoteControlStep) -> StepStatus {
        remoteStepStatuses[step] ?? .pending
    }

    private func setRemoteStatus(_ step: RemoteControlStep, _ status: StepStatus) {
        remoteStepStatuses[step] = status
    }

    private func advanceRemote(from step: RemoteControlStep) {
        setRemoteStatus(step, .completed)
        if let nextIndex = RemoteControlStep.allCases.firstIndex(of: step).map({ $0 + 1 }),
           nextIndex < RemoteControlStep.allCases.count {
            let next = RemoteControlStep.allCases[nextIndex]
            currentRemoteStep = next
            setRemoteStatus(next, .active)
        }
    }

    private func failRemote(_ step: RemoteControlStep, _ message: String) {
        setRemoteStatus(step, .failed(message))
        errorMessage = message
        isBusy = false
        statusMessage = "Error"
    }

    // MARK: - System Check

    func runSystemCheck() async {
        isBusy = true
        statusMessage = "Checking system..."

        // macOS version
        let swResult = await ShellRunner.run("sw_vers -productVersion")
        systemInfo.macOSVersion = swResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Chip
        let chipResult = await ShellRunner.run("sysctl -n machdep.cpu.brand_string")
        systemInfo.chipName = chipResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        let archResult = await ShellRunner.run("uname -m")
        let arch = archResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // RAM
        let ramResult = await ShellRunner.run("sysctl -n hw.memsize")
        if let bytes = Int64(ramResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
            systemInfo.ramGB = Int(bytes / 1_073_741_824)
        }

        // Disk space
        let dfResult = await ShellRunner.run("df -g \"$HOME\" | tail -1 | awk '{print $4}'")
        if let gb = Int(dfResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
            systemInfo.freeSpaceGB = gb
        }

        // Internet
        let netResult = await ShellRunner.run("curl -s --max-time 5 https://www.apple.com > /dev/null 2>&1 && echo ok")
        systemInfo.isConnected = netResult.output.contains("ok")

        // Validate
        let macOSMajor = Int(systemInfo.macOSVersion.split(separator: ".").first ?? "0") ?? 0
        if arch != "arm64" {
            fail(.systemCheck, "This installer requires Apple Silicon (M1/M2/M3/M4).")
            return
        }
        if macOSMajor < 12 {
            fail(.systemCheck, "macOS 12 or later is required. You have \(systemInfo.macOSVersion).")
            return
        }
        if systemInfo.ramGB < 4 {
            fail(.systemCheck, "At least 4 GB of RAM is required.")
            return
        }
        if systemInfo.freeSpaceGB < 20 {
            fail(.systemCheck, "At least 20 GB of free disk space is required.")
            return
        }
        if !systemInfo.isConnected {
            fail(.systemCheck, "No internet connection detected.")
            return
        }

        systemInfo.allPassed = true
        isBusy = false
        statusMessage = "System check passed"
        advance(from: .systemCheck)
        Task { await runInstallPrereqs() }
    }

    // MARK: - Install Prerequisites

    func runInstallPrereqs() async {
        isBusy = true
        statusMessage = "Installing software..."
        logLines = []

        prereqs = [
            PrereqStatus(name: "Xcode Command Line Tools", installed: false),
            PrereqStatus(name: "Homebrew", installed: false),
            PrereqStatus(name: "UTM", installed: false),
            PrereqStatus(name: "QEMU", installed: false),
            PrereqStatus(name: "wimlib", installed: false),
        ]

        // Create download directory
        try? FileManager.default.createDirectory(at: VMConfig.downloadDir,
                                                  withIntermediateDirectories: true)

        // 1. Xcode CLI Tools
        prereqs[0].installing = true
        let xcodeCheck = await ShellRunner.run("xcode-select -p")
        if xcodeCheck.exitCode == 0 {
            prereqs[0].installed = true
            prereqs[0].installing = false
            appendLog("Xcode CLI Tools: already installed")
        } else {
            appendLog("Installing Xcode CLI Tools...")
            let _ = await ShellRunner.run("xcode-select --install")
            // Poll until installed
            var attempts = 0
            while attempts < 360 { // 30 minutes max
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let check = await ShellRunner.run("xcode-select -p")
                if check.exitCode == 0 { break }
                attempts += 1
                if attempts % 12 == 0 {
                    appendLog("Still waiting for Xcode CLI Tools... (\(attempts * 5 / 60) min)")
                }
            }
            let finalCheck = await ShellRunner.run("xcode-select -p")
            if finalCheck.exitCode == 0 {
                prereqs[0].installed = true
                appendLog("Xcode CLI Tools installed")
            } else {
                prereqs[0].failed = true
                fail(.installPrereqs, "Xcode Command Line Tools installation timed out.")
                return
            }
            prereqs[0].installing = false
        }

        // 2. Homebrew
        prereqs[1].installing = true
        let brewCheck = await ShellRunner.run("command -v brew")
        if brewCheck.exitCode == 0 {
            prereqs[1].installed = true
            prereqs[1].installing = false
            appendLog("Homebrew: already installed")
        } else {
            appendLog("Installing Homebrew (you may be asked for your password)...")
            let brewResult = await ShellRunner.runWithAdmin(
                "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            )
            if brewResult.exitCode == 0 {
                prereqs[1].installed = true
                appendLog("Homebrew installed")
            } else {
                // Try the non-admin NONINTERACTIVE approach
                let altResult = await ShellRunner.run(
                    "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"") { [weak self] line in
                    guard let vm = self else { return }
                    Task { @MainActor in vm.appendLog(line) }
                }
                if altResult.exitCode == 0 {
                    prereqs[1].installed = true
                    appendLog("Homebrew installed")
                } else {
                    prereqs[1].failed = true
                    fail(.installPrereqs, "Homebrew installation failed. Check logs for details.")
                    return
                }
            }
            prereqs[1].installing = false
        }

        // 3. UTM
        prereqs[2].installing = true
        let utmCheck = await ShellRunner.run(
            "[ -d /Applications/UTM.app ] && echo yes || echo no")
        if utmCheck.output.contains("yes") {
            prereqs[2].installed = true
            prereqs[2].installing = false
            appendLog("UTM: already installed")
        } else {
            appendLog("Installing UTM...")
            let utmResult = await ShellRunner.run("brew install --cask utm") { [weak self] line in
                guard let vm = self else { return }
                Task { @MainActor in vm.appendLog(line) }
            }
            if utmResult.exitCode == 0 {
                prereqs[2].installed = true
                appendLog("UTM installed")
            } else {
                prereqs[2].failed = true
                fail(.installPrereqs, "UTM installation failed.")
                return
            }
            prereqs[2].installing = false
        }

        // 4. QEMU (provides qemu-img for VM disk creation)
        prereqs[3].installing = true
        let qemuCheck = await ShellRunner.run("command -v qemu-img")
        if qemuCheck.exitCode == 0 {
            prereqs[3].installed = true
            prereqs[3].installing = false
            appendLog("QEMU: already installed")
        } else {
            appendLog("Installing QEMU...")
            let qemuResult = await ShellRunner.run("brew install qemu") { [weak self] line in
                guard let vm = self else { return }
                Task { @MainActor in vm.appendLog(line) }
            }
            if qemuResult.exitCode == 0 {
                prereqs[3].installed = true
                appendLog("QEMU installed")
            } else {
                prereqs[3].failed = true
                fail(.installPrereqs, "QEMU installation failed.")
                return
            }
            prereqs[3].installing = false
        }

        // 5. wimlib
        prereqs[4].installing = true
        let wimlibCheck = await ShellRunner.run("brew list wimlib 2>/dev/null")
        if wimlibCheck.exitCode == 0 {
            prereqs[4].installed = true
            prereqs[4].installing = false
            appendLog("wimlib: already installed")
        } else {
            appendLog("Installing wimlib...")
            let wimlibResult = await ShellRunner.run("brew install wimlib") { [weak self] line in
                guard let vm = self else { return }
                Task { @MainActor in vm.appendLog(line) }
            }
            if wimlibResult.exitCode == 0 {
                prereqs[4].installed = true
                appendLog("wimlib installed")
            } else {
                prereqs[4].failed = true
                fail(.installPrereqs, "wimlib installation failed.")
                return
            }
            prereqs[4].installing = false
        }

        isBusy = false
        statusMessage = "All software installed"
        advance(from: .installPrereqs)
        Task { await runDownloadWindows() }
    }

    // MARK: - Download Windows

    func runDownloadWindows() async {
        isBusy = true
        isDownloading = true
        statusMessage = "Downloading Windows 11..."
        downloadProgress = 0
        logLines = []

        // Check for existing ISO first
        if let existing = findExistingISO() {
            windowsISOPath = existing
            appendLog("Found existing ISO: \(existing.lastPathComponent)")
            isDownloading = false
            isBusy = false
            statusMessage = "Windows ISO ready"
            advance(from: .downloadWindows)
            return
        }

        let toolsDir = VMConfig.downloadDir.appendingPathComponent("tools")
        try? FileManager.default.createDirectory(at: toolsDir, withIntermediateDirectories: true)

        // Clone download tools
        appendLog("Setting up download tools...")
        let esdDir = toolsDir.appendingPathComponent("download-windows-esd")
        if !FileManager.default.fileExists(atPath: esdDir.path) {
            let r = await ShellRunner.run(
                "git clone --depth 1 https://github.com/mattieb/download-windows-esd.git \"\(esdDir.path)\"")
            if r.exitCode != 0 {
                fail(.downloadWindows, "Failed to download ESD tool.")
                isDownloading = false
                return
            }
        }

        let isoToolDir = toolsDir.appendingPathComponent("windows-esd-to-iso")
        if !FileManager.default.fileExists(atPath: isoToolDir.path) {
            let r = await ShellRunner.run(
                "git clone --depth 1 https://github.com/mattieb/windows-esd-to-iso.git \"\(isoToolDir.path)\"")
            if r.exitCode != 0 {
                fail(.downloadWindows, "Failed to download ISO conversion tool.")
                isDownloading = false
                return
            }
        }

        let _ = await ShellRunner.run(
            "chmod +x \"\(esdDir.path)/download-windows-esd\" \"\(isoToolDir.path)/windows-esd-to-iso\"")

        appendLog("Downloading Windows 11 from Microsoft...")
        downloadStatusText = "Downloading Windows 11 (this takes a while)..."

        let downloadResult = await ShellRunner.run(
            "cd \"\(VMConfig.downloadDir.path)\" && \"\(esdDir.path)/download-windows-esd\" download en-us Professional ARM64"
        ) { [weak self] line in
            guard let vm = self else { return }
            Task { @MainActor in
                vm.appendLog(line)
                if line.contains("%") {
                    if let pct = vm.parseCurlProgress(line) {
                        vm.downloadProgress = pct
                    }
                }
            }
        }

        if downloadResult.exitCode != 0 {
            fail(.downloadWindows, "Windows download failed. You can try the manual download option.")
            isDownloading = false
            return
        }

        appendLog("Converting to ISO format...")
        downloadStatusText = "Converting to installer format..."

        // Find the ESD file
        let esdResult = await ShellRunner.run(
            "find \"\(VMConfig.downloadDir.path)\" -maxdepth 1 -iname '*.esd' -print -quit")
        let esdPath = esdResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        if !esdPath.isEmpty {
            let convResult = await ShellRunner.run(
                "cd \"\(VMConfig.downloadDir.path)\" && \"\(isoToolDir.path)/windows-esd-to-iso\" \"\(esdPath)\""
            ) { [weak self] line in
                guard let vm = self else { return }
                Task { @MainActor in vm.appendLog(line) }
            }

            if convResult.exitCode != 0 {
                fail(.downloadWindows, "ISO conversion failed.")
                isDownloading = false
                return
            }
            // Clean up ESD
            try? FileManager.default.removeItem(atPath: esdPath)
        }

        // Find resulting ISO
        if let iso = findExistingISO() {
            windowsISOPath = iso
            appendLog("Windows ISO ready: \(iso.lastPathComponent)")
        } else {
            fail(.downloadWindows, "Could not find the converted ISO file.")
            isDownloading = false
            return
        }

        // Download SPICE tools
        appendLog("Downloading SPICE Guest Tools...")
        downloadStatusText = "Downloading SPICE Guest Tools..."
        let spiceDest = VMConfig.downloadDir.appendingPathComponent("spice-guest-tools.exe")
        if !FileManager.default.fileExists(atPath: spiceDest.path) {
            let _ = await ShellRunner.run(
                "curl -L -o \"\(spiceDest.path)\" \"\(VMConfig.spiceToolsURL)\"")
        }

        isDownloading = false
        isBusy = false
        statusMessage = "Download complete"
        advance(from: .downloadWindows)
    }

    // MARK: - Create VM

    func runCreateVM() async {
        guard let isoPath = windowsISOPath else {
            fail(.createVM, "No Windows ISO found.")
            return
        }

        isBusy = true
        statusMessage = "Creating virtual machine..."

        let vmDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/\(VMConfig.name).utm")

        // Check if a valid VM already exists (has a disk image, not just a partial directory)
        if FileManager.default.fileExists(atPath: vmDir.path) {
            let dataDir = vmDir.appendingPathComponent("Data")
            let hasQcow2 = (try? FileManager.default.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil))?
                .contains(where: { $0.pathExtension == "qcow2" }) ?? false

            if hasQcow2 {
                vmPath = vmDir
                statusMessage = "VM already exists"
                isBusy = false
                advance(from: .createVM)
                return
            } else {
                // Partial/failed previous attempt — clean up
                try? FileManager.default.removeItem(at: vmDir)
            }
        }

        do {
            let dir = try await VMCreator.createVMBundle(
                isoPath: isoPath,
                vmRAM: systemInfo.vmRAM,
                vmCores: systemInfo.vmCores
            )
            vmPath = dir

            // Open in UTM
            let _ = await ShellRunner.run("open \"\(dir.path)\"")
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            isBusy = false
            statusMessage = "VM created"
            advance(from: .createVM)
        } catch {
            fail(.createVM, "Failed to create VM: \(error.localizedDescription)")
        }
    }

    // MARK: - Install Windows (user-guided)

    func confirmWindowsInstalled() {
        advance(from: .installWindows)
        statusMessage = "All done!"
    }

    // MARK: - Manual ISO selection

    func selectISOManually() {
        let panel = NSOpenPanel()
        panel.title = "Select Windows 11 ARM ISO"
        panel.allowedContentTypes = [.init(filenameExtension: "iso")!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            windowsISOPath = url
            errorMessage = nil
            setStatus(.downloadWindows, .completed)
            if currentStep == .downloadWindows {
                advance(from: .downloadWindows)
            }
        }
    }

    // MARK: - Retry

    func retry() {
        errorMessage = nil

        if currentScreen == .remoteControl {
            let step = currentRemoteStep
            setRemoteStatus(step, .active)
            isBusy = false

            Task {
                switch step {
                case .installAnyDesk: await runInstallAnyDesk()
                default: break
                }
            }
            return
        }

        let step = currentStep
        setStatus(step, .active)
        isBusy = false

        Task {
            switch step {
            case .systemCheck:    await runSystemCheck()
            case .installPrereqs: await runInstallPrereqs()
            case .downloadWindows: await runDownloadWindows()
            case .createVM:       await runCreateVM()
            default: break
            }
        }
    }

    // MARK: - Install AnyDesk

    func runInstallAnyDesk() async {
        isBusy = true
        statusMessage = "Installing AnyDesk..."
        logLines = []

        // Check if already installed
        let check = await ShellRunner.run("[ -d /Applications/AnyDesk.app ] && echo yes || echo no")
        if check.output.contains("yes") {
            remoteControlInfo.anyDeskInstalled = true
            appendLog("AnyDesk: already installed")
            isBusy = false
            statusMessage = "AnyDesk installed"
            advanceRemote(from: .installAnyDesk)
            return
        }

        // Check for Homebrew first
        let brewCheck = await ShellRunner.run("command -v brew")
        if brewCheck.exitCode != 0 {
            appendLog("Installing Homebrew first...")
            let brewResult = await ShellRunner.run(
                "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"") { [weak self] line in
                guard let vm = self else { return }
                Task { @MainActor in vm.appendLog(line) }
            }
            if brewResult.exitCode != 0 {
                failRemote(.installAnyDesk, "Homebrew installation failed. AnyDesk requires Homebrew to install.")
                return
            }
            appendLog("Homebrew installed")
        }

        // Install AnyDesk via brew
        appendLog("Installing AnyDesk...")
        let result = await ShellRunner.run("brew install --cask anydesk") { [weak self] line in
            guard let vm = self else { return }
            Task { @MainActor in vm.appendLog(line) }
        }

        if result.exitCode == 0 {
            remoteControlInfo.anyDeskInstalled = true
            appendLog("AnyDesk installed successfully")
            isBusy = false
            statusMessage = "AnyDesk installed"
            advanceRemote(from: .installAnyDesk)
        } else {
            failRemote(.installAnyDesk, "AnyDesk installation failed. Check logs for details.")
        }
    }

    // MARK: - Permissions

    func openScreenRecordingSettings() {
        let _ = Task {
            await ShellRunner.run("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'")
        }
    }

    func openAccessibilitySettings() {
        let _ = Task {
            await ShellRunner.run("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'")
        }
    }

    func confirmPermissionsGranted() {
        remoteControlInfo.screenRecordingGranted = true
        remoteControlInfo.accessibilityGranted = true
        advanceRemote(from: .permissions)
        statusMessage = "Permissions granted"
    }

    // MARK: - Unattended Access

    func openAnyDeskPreferences() {
        let _ = Task {
            await ShellRunner.run("open /Applications/AnyDesk.app")
        }
    }

    func confirmUnattendedAccess() {
        remoteControlInfo.unattendedAccessSet = true
        advanceRemote(from: .unattendedAccess)
        statusMessage = "Unattended access configured"
        // Try to fetch the address
        Task { await fetchAnyDeskAddress() }
    }

    // MARK: - Share Address

    func fetchAnyDeskAddress() async {
        // Try CLI approach first
        let result = await ShellRunner.run("/Applications/AnyDesk.app/Contents/MacOS/AnyDesk --get-id 2>/dev/null")
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0 && !output.isEmpty && output.allSatisfy({ $0.isNumber || $0 == " " }) {
            remoteControlInfo.anyDeskAddress = output
        }
    }

    // MARK: - Uninstall

    func scanForArtifacts() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")

        let candidates: [(id: String, name: String, path: URL)] = [
            ("vm", "Windows 11 VM", home.appendingPathComponent("Documents/Windows 11.utm")),
            ("downloads", "Downloaded files", VMConfig.downloadDir),
            ("utm", "UTM.app", URL(fileURLWithPath: "/Applications/UTM.app")),
            ("wimlib", "wimlib", URL(fileURLWithPath: "/opt/homebrew/Cellar/wimlib")),
            ("qemu", "QEMU", URL(fileURLWithPath: "/opt/homebrew/Cellar/qemu")),
            ("utm-prefs", "UTM preferences", library.appendingPathComponent("Preferences/com.utmapp.UTM.plist")),
            ("utm-containers", "UTM app data", library.appendingPathComponent("Containers/com.utmapp.UTM")),
            ("utm-appsupp", "UTM support files", library.appendingPathComponent("Application Support/com.utmapp.UTM")),
            ("utm-saved", "UTM saved state", library.appendingPathComponent("Saved Application State/com.utmapp.UTM.savedState")),
            ("utm-caches", "UTM caches", library.appendingPathComponent("Caches/com.utmapp.UTM")),
            ("utm-logs", "UTM logs", library.appendingPathComponent("Logs/com.utmapp.UTM")),
        ]

        uninstallItems = candidates.compactMap { item in
            let exists = fm.fileExists(atPath: item.path.path)
            guard exists else { return nil }
            let size: Int64 = directorySize(item.path) ?? 0
            return UninstallItem(
                id: item.id,
                name: item.name,
                detail: item.path.path,
                sizeBytes: size,
                exists: true
            )
        }
    }

    func runUninstall() async {
        isUninstalling = true
        let fm = FileManager.default

        for i in uninstallItems.indices where uninstallItems[i].selected {
            uninstallItems[i].deleting = true

            let item = uninstallItems[i]
            var success = false

            switch item.id {
            case "utm":
                let result = await ShellRunner.run("brew uninstall --cask utm 2>/dev/null; rm -rf /Applications/UTM.app")
                success = !fm.fileExists(atPath: "/Applications/UTM.app")
                if !success && result.exitCode != 0 {
                    // Try direct removal
                    try? fm.removeItem(atPath: "/Applications/UTM.app")
                    success = !fm.fileExists(atPath: "/Applications/UTM.app")
                }
            case "wimlib":
                let result = await ShellRunner.run("brew uninstall wimlib")
                success = result.exitCode == 0
            case "qemu":
                let result = await ShellRunner.run("brew uninstall qemu")
                success = result.exitCode == 0
            default:
                do {
                    try fm.removeItem(atPath: item.detail)
                    success = !fm.fileExists(atPath: item.detail)
                } catch {
                    // FileManager can fail on protected directories — try rm -rf
                    let _ = await ShellRunner.run("rm -rf \"\(item.detail)\"")
                    success = !fm.fileExists(atPath: item.detail)
                }
            }

            uninstallItems[i].deleting = false
            if success {
                uninstallItems[i].deleted = true
                uninstallItems[i].selected = false
            } else {
                uninstallItems[i].failed = true
            }
        }

        isUninstalling = false
    }

    private func directorySize(_ url: URL) -> Int64? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url,
                                              includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                              options: [.skipsHiddenFiles]) else {
            // Single file
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                return size
            }
            return nil
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    // MARK: - Helpers

    private func findExistingISO() -> URL? {
        let fm = FileManager.default
        let searchDirs = [
            VMConfig.downloadDir,
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
        ]

        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
                continue
            }
            for item in items where item.pathExtension.lowercased() == "iso" {
                if let size = try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 3_000_000_000 {
                    return item
                }
            }
        }
        return nil
    }

    private func parseCurlProgress(_ line: String) -> Double? {
        // curl progress lines often contain something like " 58.3%"
        let pattern = #"(\d+\.?\d*)%"#
        if let range = line.range(of: pattern, options: .regularExpression),
           let val = Double(line[range].dropLast()) {
            return val / 100.0
        }
        return nil
    }
}
