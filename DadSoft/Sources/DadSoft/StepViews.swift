import SwiftUI
import Contacts

// MARK: - System Check

struct SystemCheckView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Checking Your Mac")
                .font(.title2)
                .fontWeight(.bold)

            if vm.isBusy {
                ProgressView("Running system checks...")
                    .padding(.vertical)
            }

            if !vm.systemInfo.macOSVersion.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    checkRow("macOS version", vm.systemInfo.macOSVersion, passed: true)
                    checkRow("Processor", vm.systemInfo.chipName, passed: true)
                    checkRow("Memory", "\(vm.systemInfo.ramGB) GB", passed: vm.systemInfo.ramGB >= 4)
                    checkRow("Free space", "\(vm.systemInfo.freeSpaceGB) GB", passed: vm.systemInfo.freeSpaceGB >= 20)
                    checkRow("Internet", vm.systemInfo.isConnected ? "Connected" : "Not connected",
                             passed: vm.systemInfo.isConnected)
                }

                if vm.systemInfo.allPassed {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Your Mac is compatible!")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 8)

                    Text("VM will use \(vm.systemInfo.vmRAM / 1024) GB RAM and \(vm.systemInfo.vmCores) CPU cores")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = vm.errorMessage {
                ErrorBox(message: error)
                Button("Retry") { vm.retry() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func checkRow(_ label: String, _ value: String, passed: Bool) -> some View {
        HStack {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(passed ? .green : .red)
                .frame(width: 20)
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Prerequisites

struct PrereqsView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Installing Required Software")
                .font(.title2)
                .fontWeight(.bold)

            ForEach(Array(vm.prereqs.enumerated()), id: \.element.id) { _, prereq in
                HStack {
                    if prereq.installing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 20, height: 20)
                    } else if prereq.installed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .frame(width: 20)
                    } else if prereq.failed {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .frame(width: 20)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                    }
                    Text(prereq.name)
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            if !vm.logLines.isEmpty {
                LogScrollView()
            }

            if let error = vm.errorMessage {
                ErrorBox(message: error)
                Button("Retry") { vm.retry() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Download Windows

struct DownloadView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Downloading Windows 11")
                .font(.title2)
                .fontWeight(.bold)

            if vm.isDownloading {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: vm.downloadProgress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text(String(format: "%.0f%%", vm.downloadProgress * 100))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Spacer()
                        if !vm.downloadStatusText.isEmpty {
                            Text(vm.downloadStatusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)

                Text("You can keep using your Mac while this downloads.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            if vm.windowsISOPath != nil && !vm.isDownloading {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Windows 11 ISO ready")
                        .fontWeight(.medium)
                }
            }

            if !vm.logLines.isEmpty {
                LogScrollView()
            }

            if let error = vm.errorMessage {
                ErrorBox(message: error)

                HStack(spacing: 12) {
                    Button("Retry Download") { vm.retry() }
                        .buttonStyle(.borderedProminent)
                    Button("Select ISO File...") { vm.selectISOManually() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

// MARK: - Create VM

struct CreateVMView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Creating Virtual Machine")
                .font(.title2)
                .fontWeight(.bold)

            if vm.isBusy {
                ProgressView("Setting up the virtual machine...")
                    .padding(.vertical)
            } else if vm.vmPath == nil {
                Text("Ready to create the Windows 11 virtual machine.")
                    .foregroundColor(.secondary)

                Button("Create VM") {
                    Task { await vm.runCreateVM() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Virtual machine created and opened in UTM!")
                        .fontWeight(.medium)
                }
            }

            if let error = vm.errorMessage {
                ErrorBox(message: error)
                Button("Retry") { vm.retry() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Install Windows

struct InstallWindowsView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install Windows 11")
                .font(.title2)
                .fontWeight(.bold)

            Text("Follow these steps in UTM to install Windows:")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                instructionStep(1, "Start the VM",
                    "Click on \"\(VMConfig.name)\" in UTM's sidebar, then click the Play button.")
                instructionStep(2, "Boot from DVD",
                    "If you see \"Press any key to boot from CD or DVD\", press any key quickly.")
                instructionStep(3, "Language & Install",
                    "Select your language, click Next, then click \"Install now\".")
                instructionStep(4, "Product key",
                    "Enter your key, or click \"I don't have a product key\" to enter it later.")
                instructionStep(5, "Custom install",
                    "Choose \"Custom: Install Windows only\", select the drive, click Next.")
                instructionStep(6, "Wait",
                    "Windows will install and restart. This takes 10\u{2013}15 minutes. Don't close UTM.")
                instructionStep(7, "Setup wizard",
                    "Follow the on-screen prompts: connect to your network, set up your account, PIN, and privacy settings.")
            }

            Spacer()

            HStack {
                Spacer()
                Button("Windows Is Installed") {
                    vm.confirmWindowsInstalled()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func instructionStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Complete

struct CompleteView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.green)
                Text("All Done!")
                    .font(.title)
                    .fontWeight(.bold)
            }

            Text("Windows 11 has been successfully set up on your Mac!")
                .font(.body)

            VStack(alignment: .leading, spacing: 8) {
                Text("How to use:")
                    .font(.headline)
                bulletPoint("Open UTM from your Applications folder")
                bulletPoint("Select \"\(VMConfig.name)\" from the sidebar")
                bulletPoint("Click the Play button")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard shortcuts:")
                    .font(.headline)
                HStack {
                    Text("Control + Option")
                        .font(.system(.body, design: .monospaced))
                    Text("Release mouse from VM")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Command key")
                        .font(.system(.body, design: .monospaced))
                    Text("Acts as Windows key")
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Important:")
                    .font(.headline)
                bulletPoint("Always shut down Windows properly via Start menu")
                bulletPoint("Keep UTM updated for best performance")
            }

            Spacer()

            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.system(size: 12))

                Spacer()

                Button("Back to Hub") {
                    vm.returnToHub()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Open UTM") {
                    Task {
                        await ShellRunner.run("open /Applications/UTM.app")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}

// MARK: - Install AnyDesk

struct InstallAnyDeskView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Installing AnyDesk")
                .font(.title2)
                .fontWeight(.bold)

            if vm.isBusy {
                ProgressView("Installing AnyDesk...")
                    .padding(.vertical)
            } else if vm.remoteControlInfo.anyDeskInstalled {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("AnyDesk is installed!")
                        .fontWeight(.medium)
                }
            }

            if !vm.logLines.isEmpty {
                LogScrollView()
            }

            if let error = vm.errorMessage {
                ErrorBox(message: error)
                Button("Retry") { vm.retry() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Permissions

struct PermissionsView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grant Permissions")
                .font(.title2)
                .fontWeight(.bold)

            Text("AnyDesk needs two macOS permissions to let your son see and control your screen.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("1. Screen Recording")
                    .font(.headline)
                Text("This lets AnyDesk share your screen so your son can see it.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Button("Open Screen Recording Settings") {
                    vm.openScreenRecordingSettings()
                }
                .buttonStyle(.bordered)

                bulletPoint("Click the + button")
                bulletPoint("Navigate to Applications and select AnyDesk")
                bulletPoint("Toggle it ON")
                bulletPoint("If prompted, click \"Quit & Reopen\"")
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("2. Accessibility")
                    .font(.headline)
                Text("This lets AnyDesk control your mouse and keyboard remotely.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Button("Open Accessibility Settings") {
                    vm.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)

                bulletPoint("Click the + button")
                bulletPoint("Navigate to Applications and select AnyDesk")
                bulletPoint("Toggle it ON")
            }

            Spacer()

            HStack {
                Spacer()
                Button("I've Granted Both Permissions") {
                    vm.confirmPermissionsGranted()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}

// MARK: - Unattended Access

struct UnattendedAccessView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Up Unattended Access")
                .font(.title2)
                .fontWeight(.bold)

            Text("This lets your son connect even when you're not sitting at the computer.")
                .foregroundColor(.secondary)

            Button("Open AnyDesk") {
                vm.openAnyDeskPreferences()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 20) {
                // Step 1: Open menu
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 1: Open the menu")
                        .font(.headline)
                    Text("Click the hamburger menu (three lines) in the top-right corner of AnyDesk.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    instructionImage("anydesk-step1-menu")
                }

                // Step 2: Open Settings
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 2: Open Settings")
                        .font(.headline)
                    Text("Click \"Settings\" in the dropdown menu.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    instructionImage("anydesk-step2-settings")
                }

                // Step 3: Set password
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 3: Set a password")
                        .font(.headline)
                    Text("Click \"Access\" under Security in the left sidebar, then click \"Set password\" under Unattended Access.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    instructionImage("anydesk-step3-access")
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("I've Set Up Unattended Access") {
                    vm.confirmUnattendedAccess()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func instructionImage(_ name: String) -> some View {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 300)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

// MARK: - Share Address

struct ShareAddressView: View {
    @EnvironmentObject var vm: InstallerViewModel
    @State private var copied = false
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.green)
                Text("All Set!")
                    .font(.title)
                    .fontWeight(.bold)
            }

            Text("AnyDesk is installed and configured for remote access.")
                .font(.body)

            if !vm.remoteControlInfo.anyDeskAddress.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your AnyDesk Address:")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Text(vm.remoteControlInfo.anyDeskAddress)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)

                        Button(copied ? "Copied!" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(vm.remoteControlInfo.anyDeskAddress, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copied = false
                            }
                        }
                        .buttonStyle(.bordered)

                        if !vm.sonPhone.isEmpty {
                            Button(sent ? "Sent!" : "Send to \(vm.sonName)") {
                                let text = "Here's my AnyDesk address so you can remote in: \(vm.remoteControlInfo.anyDeskAddress)"
                                Task {
                                    await vm.sendMessageToSon(text)
                                    sent = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        sent = false
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(sent)
                        } else {
                            Button("Share via Messages") {
                                let text = "Here's my AnyDesk address so you can remote in: \(vm.remoteControlInfo.anyDeskAddress)"
                                let picker = NSSharingServicePicker(items: [text])
                                if let window = NSApp.keyWindow,
                                   let contentView = window.contentView {
                                    picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your AnyDesk Address:")
                        .font(.headline)
                    Text("Open AnyDesk to find your address displayed on the main screen.")
                        .foregroundColor(.secondary)
                    Button("Open AnyDesk") {
                        vm.openAnyDeskPreferences()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(vm.sonName.isEmpty ? "What to tell your son:" : "What to tell \(vm.sonName):")
                    .font(.headline)
                bulletPoint("Give him your AnyDesk address (the number above)")
                bulletPoint("Give him the unattended access password you set")
                bulletPoint("He installs AnyDesk on his computer too")
                bulletPoint("He enters your address and password to connect")
            }

            Spacer()

            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.system(size: 12))

                Spacer()

                Button("Back to Hub") {
                    vm.returnToHub()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}

// MARK: - Uninstall

struct UninstallView: View {
    @EnvironmentObject var vm: InstallerViewModel
    @State private var showConfirm = false

    private var selectedCount: Int {
        vm.uninstallItems.filter { $0.selected && !$0.deleted }.count
    }

    private var selectedSize: Int64 {
        vm.uninstallItems.filter { $0.selected && !$0.deleted }.reduce(0) { $0 + $1.sizeBytes }
    }

    private var allDone: Bool {
        !vm.uninstallItems.isEmpty && vm.uninstallItems.allSatisfy { $0.deleted || $0.failed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uninstall")
                .font(.title2)
                .fontWeight(.bold)

            Text("Select items to remove from your Mac:")
                .foregroundColor(.secondary)

            if vm.uninstallItems.isEmpty {
                Text("Nothing found to uninstall.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.uninstallItems.indices, id: \.self) { i in
                            uninstallRow(index: i)
                            if i < vm.uninstallItems.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
            }

            Spacer()

            HStack {
                if allDone {
                    Spacer()
                    Button("Done") {
                        vm.showUninstall = false
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if selectedCount > 0 {
                        Text("\(selectedCount) selected \u{2014} \(formatBytes(selectedSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Cancel") {
                        vm.showUninstall = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isUninstalling)

                    Button("Delete Selected") {
                        showConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selectedCount == 0 || vm.isUninstalling)
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 550)
        .alert("Confirm Deletion", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await vm.runUninstall() }
            }
        } message: {
            Text("This will permanently delete \(selectedCount) item(s) (\(formatBytes(selectedSize))). This cannot be undone.")
        }
    }

    private func uninstallRow(index i: Int) -> some View {
        let item = vm.uninstallItems[i]
        return HStack(spacing: 10) {
            if item.deleting {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
            } else if item.deleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .frame(width: 20)
            } else if item.failed {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .frame(width: 20)
            } else {
                Toggle("", isOn: Binding(
                    get: { vm.uninstallItems[i].selected },
                    set: { vm.uninstallItems[i].selected = $0 }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(item.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(item.sizeString)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(item.deleted ? 0.5 : 1.0)
    }
}

// MARK: - Son Setup (Contact Picker)

struct SonSetupView: View {
    @EnvironmentObject var vm: InstallerViewModel
    @State private var searchText = ""
    @State private var showManual = false
    @State private var manualName = ""
    @State private var manualPhone = ""
    @State private var contactsAccessDenied = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Who is your son?")
                .font(.title)
                .fontWeight(.bold)

            Text("Pick him from your contacts so we can\nsend him your info directly via Messages.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if !showManual {
                TextField("Search contacts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { query in
                        requestAccessAndSearch(query)
                    }

                if contactsAccessDenied {
                    VStack(spacing: 8) {
                        Text("Contacts access was denied.")
                            .foregroundColor(.secondary)
                        Text("You can grant access in System Settings > Privacy & Security > Contacts, or enter a number manually below.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 8)
                } else if !vm.contactResults.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(vm.contactResults) { contact in
                                Button {
                                    vm.saveSonContact(name: contact.name, phone: contact.phone)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(contact.name)
                                                .font(.body)
                                                .fontWeight(.medium)
                                                .foregroundColor(.primary)
                                            Text("\(contact.phoneLabel): \(contact.phone)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if contact.id != vm.contactResults.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .frame(maxHeight: 200)
                } else if !searchText.isEmpty {
                    Text("No contacts found")
                        .foregroundColor(.secondary)
                        .frame(maxHeight: 200)
                } else {
                    Text("Start typing a name to search")
                        .foregroundColor(.secondary)
                        .frame(maxHeight: 200)
                }

                Button("Enter phone number manually instead") {
                    showManual = true
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name", text: $manualName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Phone number or iMessage email", text: $manualPhone)
                        .textFieldStyle(.roundedBorder)
                }

                Button("Search contacts instead") {
                    showManual = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.caption)

                Spacer()
            }

            HStack {
                Button("Skip") {
                    vm.showSonSetup = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                if showManual {
                    Button("Save") {
                        vm.saveSonContact(name: manualName, phone: manualPhone)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(manualName.isEmpty || manualPhone.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 450, height: 520)
    }

    private func requestAccessAndSearch(_ query: String) {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .denied || status == .restricted {
            contactsAccessDenied = true
            return
        }
        if status == .notDetermined {
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        vm.searchContacts(query)
                    } else {
                        contactsAccessDenied = true
                    }
                }
            }
        } else {
            vm.searchContacts(query)
        }
    }
}

// MARK: - Shared Components

func bulletPoint(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
        Text("\u{2022}")
            .foregroundColor(.secondary)
        Text(text)
    }
    .font(.body)
}

struct ErrorBox: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.callout)
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

struct LogScrollView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Log")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(vm.logLines.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .frame(height: 100)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .onChange(of: vm.logLines.count) { _ in
                    if let last = vm.logLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }
}
