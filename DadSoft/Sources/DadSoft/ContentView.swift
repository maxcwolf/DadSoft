import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar

            Divider()

            // Main content switches on current screen
            switch vm.currentScreen {
            case .hub:
                hubView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .windowsInstaller:
                HStack(spacing: 0) {
                    windowsSidebar
                        .frame(width: 180)

                    Divider()

                    windowsDetailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

            case .remoteControl:
                HStack(spacing: 0) {
                    remoteControlSidebar
                        .frame(width: 180)

                    Divider()

                    remoteControlDetailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            // Bottom status bar
            statusBar
        }
        .frame(width: 900, height: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $vm.showUninstall) {
            UninstallView()
                .environmentObject(vm)
        }
        .sheet(isPresented: $vm.showSonSetup) {
            SonSetupView()
                .environmentObject(vm)
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            if vm.currentScreen != .hub {
                Button(action: { vm.returnToHub() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Hub")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

            Text("\u{1F43A}")
                .font(.title2)
            Text("DadSoft")
                .font(.headline)
                .fontWeight(.bold)
            Text("\u{2014}")
                .foregroundColor(.secondary)
            Text(subtitleText)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var subtitleText: String {
        switch vm.currentScreen {
        case .hub:              return "Dad's Toolkit"
        case .windowsInstaller: return "Windows 11 Installer"
        case .remoteControl:    return "Remote Control Setup"
        }
    }

    // MARK: - Hub View

    private var hubView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                // Quick-action row — appears as features are completed
                if vm.anyDeskReady || vm.windowsVMReady {
                    HStack(spacing: 20) {
                        if vm.anyDeskReady {
                            hubCard(
                                title: vm.sonName.isEmpty
                                    ? "Let My Son Take\nOver My Computer"
                                    : "Let \(vm.sonName) Take\nOver My Computer",
                                icon: "display",
                                style: .filled(.blue)
                            ) {
                                vm.launchAnyDeskAndShare()
                            }
                        }

                        if vm.windowsVMReady {
                            hubCard(
                                title: "Open\nWindows 11",
                                icon: "laptopcomputer",
                                style: .filled(.purple)
                            ) {
                                vm.launchWindowsVM()
                            }
                        }
                    }
                }

                // Setup row — always visible
                HStack(spacing: 20) {
                    hubCard(
                        title: "Set Up Remote Control\nFor Your Son",
                        icon: "display",
                        style: vm.anyDeskReady ? .completed : .outline(.blue)
                    ) {
                        vm.navigateTo(.remoteControl)
                    }

                    hubCard(
                        title: "Set Up Windows\nOn Your Mac",
                        icon: "laptopcomputer",
                        style: vm.windowsVMReady ? .completed : .outline(.purple)
                    ) {
                        vm.navigateTo(.windowsInstaller)
                    }
                }
            }

            Spacer()

            HStack {
                Button("Uninstall...") {
                    vm.scanForArtifacts()
                    vm.showUninstall = true
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button(action: { vm.showSonSetup = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                        if !vm.sonName.isEmpty {
                            Text(vm.sonName)
                            Text("(change)")
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        } else {
                            Text("Set up contact")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(16)
        }
        .onAppear {
            vm.scanInstalledFeatures()
            vm.loadSonContact()
        }
        .onChange(of: vm.showUninstall) { showing in
            if !showing {
                vm.scanInstalledFeatures()
            }
        }
    }

    // MARK: - Hub Card

    private enum HubCardStyle {
        case outline(Color)
        case filled(Color)
        case completed
    }

    private func hubCard(title: String, icon: String, style: HubCardStyle, action: @escaping () -> Void) -> some View {
        let icoColor: Color
        let txtColor: Color
        let bg: Color
        let border: Color
        let bw: CGFloat
        let showCheck: Bool

        switch style {
        case .outline(let c):
            icoColor = c; txtColor = .primary
            bg = Color(nsColor: .controlBackgroundColor)
            border = Color.secondary.opacity(0.2); bw = 1; showCheck = false
        case .filled(let c):
            icoColor = .white; txtColor = .white
            bg = c; border = .clear; bw = 0; showCheck = false
        case .completed:
            icoColor = .green; txtColor = .primary
            bg = Color(nsColor: .controlBackgroundColor)
            border = Color.green.opacity(0.5); bw = 2; showCheck = true
        }

        return Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(icoColor)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(txtColor)
            }
            .frame(width: 200, height: 200)
            .background(bg)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(border, lineWidth: bw)
            )
            .overlay(alignment: .topTrailing) {
                if showCheck {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Windows Installer Sidebar

    private var windowsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(InstallStep.allCases) { step in
                sidebarRow(step.title, status: vm.status(for: step), isActive: step == vm.currentStep)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Remote Control Sidebar

    private var remoteControlSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(RemoteControlStep.allCases) { step in
                sidebarRow(step.title, status: vm.remoteStatus(for: step), isActive: step == vm.currentRemoteStep)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Shared Sidebar Row

    private func sidebarRow(_ title: String, status: StepStatus, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: status.icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor(for: status))
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .primary : .secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 4)
    }

    private func iconColor(for status: StepStatus) -> Color {
        switch status {
        case .pending:   return .secondary
        case .active:    return .accentColor
        case .completed: return .green
        case .failed:    return .red
        }
    }

    // MARK: - Windows Detail Panel

    private var windowsDetailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch vm.currentStep {
                case .systemCheck:    SystemCheckView()
                case .installPrereqs: PrereqsView()
                case .downloadWindows: DownloadView()
                case .createVM:       CreateVMView()
                case .installWindows: InstallWindowsView()
                case .complete:       CompleteView()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Remote Control Detail Panel

    private var remoteControlDetailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch vm.currentRemoteStep {
                case .installAnyDesk:   InstallAnyDeskView()
                case .permissions:      PermissionsView()
                case .unattendedAccess: UnattendedAccessView()
                case .share:            ShareAddressView()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Spacer()
            if vm.isBusy {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
            Text(vm.statusMessage)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
