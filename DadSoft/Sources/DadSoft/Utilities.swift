import Foundation

// MARK: - Shell Runner

private final class OutputCollector: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func joined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined()
    }
}

actor ShellRunner {
    struct Result {
        let exitCode: Int32
        let output: String
    }

    static func run(_ command: String, onOutput: (@Sendable (String) -> Void)? = nil) async -> Result {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        // Inherit Homebrew PATH
        var env = ProcessInfo.processInfo.environment
        let brewPath = "/opt/homebrew/bin:/opt/homebrew/sbin"
        env["PATH"] = brewPath + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        let output = OutputCollector()
        let handle = pipe.fileHandleForReading

        handle.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            output.append(line)
            onOutput?(line)
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return Result(exitCode: -1, output: "Failed to launch: \(error.localizedDescription)")
        }

        handle.readabilityHandler = nil
        if let remaining = String(data: handle.readDataToEndOfFile(), encoding: .utf8), !remaining.isEmpty {
            output.append(remaining)
        }

        return Result(exitCode: process.terminationStatus, output: output.joined())
    }

    static func runWithAdmin(_ command: String) async -> Result {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let (output, success) = await MainActor.run { () -> (String, Bool) in
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            let descriptor = appleScript?.executeAndReturnError(&error)
            if let error = error {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                return (msg, false)
            }
            return (descriptor?.stringValue ?? "", true)
        }

        return Result(exitCode: success ? 0 : 1, output: output)
    }
}

// MARK: - File Downloader

final class FileDownloader: NSObject, URLSessionDownloadDelegate, Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private let continuation: UnsafeContinuation<URL, Error>

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void,
         continuation: UnsafeContinuation<URL, Error>) {
        self.onProgress = onProgress
        self.continuation = continuation
    }

    static func download(url: URL, to destination: URL,
                         onProgress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        try await withUnsafeThrowingContinuation { continuation in
            let delegate = FileDownloader(onProgress: onProgress, continuation: continuation)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            objc_setAssociatedObject(task, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        continuation.resume(returning: location)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - VM Creator (QEMU Backend)

enum VMCreator {
    static let qemuImg = "/opt/homebrew/bin/qemu-img"

    static func createVMBundle(
        isoPath: URL,
        vmRAM: Int,
        vmCores: Int
    ) async throws -> URL {
        let vmDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/\(VMConfig.name).utm")
        let dataDir = vmDir.appendingPathComponent("Data")

        if FileManager.default.fileExists(atPath: vmDir.path) {
            return vmDir
        }

        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        // Create qcow2 disk image using UTM's bundled qemu-img
        let driveUUID = UUID().uuidString
        let diskPath = dataDir.appendingPathComponent("\(driveUUID).qcow2")
        let imgResult = await ShellRunner.run(
            "\"\(qemuImg)\" create -f qcow2 \"\(diskPath.path)\" \(VMConfig.diskSizeGB)G"
        )
        if imgResult.exitCode != 0 {
            throw NSError(domain: "VMCreator", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create disk image: \(imgResult.output)"])
        }

        // Copy ISO into the VM bundle
        let isoUUID = UUID().uuidString
        let isoName = "\(isoUUID).iso"
        let isoDest = dataDir.appendingPathComponent(isoName)
        try FileManager.default.copyItem(at: isoPath, to: isoDest)

        // Generate config
        let vmUUID = UUID().uuidString
        let macAddr = String(format: "52:54:00:%02X:%02X:%02X",
                             Int.random(in: 0...255),
                             Int.random(in: 0...255),
                             Int.random(in: 0...255))

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Backend</key>
            <string>QEMU</string>
            <key>ConfigurationVersion</key>
            <integer>4</integer>
            <key>Information</key>
            <dict>
                <key>Name</key>
                <string>\(VMConfig.name)</string>
                <key>IconCustom</key>
                <false/>
                <key>Icon</key>
                <string>windows</string>
                <key>UUID</key>
                <string>\(vmUUID)</string>
            </dict>
            <key>System</key>
            <dict>
                <key>Architecture</key>
                <string>aarch64</string>
                <key>CPU</key>
                <string>default</string>
                <key>CPUCount</key>
                <integer>\(vmCores)</integer>
                <key>CPUFlagsAdd</key>
                <array/>
                <key>CPUFlagsRemove</key>
                <array/>
                <key>ForceMulticore</key>
                <false/>
                <key>JITCacheSize</key>
                <integer>0</integer>
                <key>MemorySize</key>
                <integer>\(vmRAM)</integer>
                <key>Target</key>
                <string>virt</string>
            </dict>
            <key>QEMU</key>
            <dict>
                <key>AdditionalArguments</key>
                <array/>
                <key>BalloonDevice</key>
                <true/>
                <key>DebugLog</key>
                <false/>
                <key>Hypervisor</key>
                <true/>
                <key>PS2Controller</key>
                <false/>
                <key>RNGDevice</key>
                <true/>
                <key>RTCLocalTime</key>
                <true/>
                <key>TPMDevice</key>
                <true/>
                <key>TSO</key>
                <false/>
                <key>UEFIBoot</key>
                <true/>
            </dict>
            <key>Input</key>
            <dict>
                <key>MaximumUsbShare</key>
                <integer>3</integer>
                <key>UsbBusSupport</key>
                <string>3.0</string>
                <key>UsbSharing</key>
                <true/>
            </dict>
            <key>Sharing</key>
            <dict>
                <key>ClipboardSharing</key>
                <true/>
                <key>DirectoryShareMode</key>
                <string>WebDAV</string>
                <key>DirectoryShareReadOnly</key>
                <false/>
            </dict>
            <key>Display</key>
            <array>
                <dict>
                    <key>DynamicResolution</key>
                    <true/>
                    <key>Hardware</key>
                    <string>virtio-ramfb-gl</string>
                    <key>NativeResolution</key>
                    <false/>
                    <key>UpscalingFilter</key>
                    <string>Nearest</string>
                    <key>DownscalingFilter</key>
                    <string>Linear</string>
                </dict>
            </array>
            <key>Drive</key>
            <array>
                <dict>
                    <key>Identifier</key>
                    <string>\(isoUUID)</string>
                    <key>ImageName</key>
                    <string>\(isoName)</string>
                    <key>ImageType</key>
                    <string>CD</string>
                    <key>Interface</key>
                    <string>USB</string>
                    <key>InterfaceVersion</key>
                    <integer>1</integer>
                    <key>ReadOnly</key>
                    <true/>
                </dict>
                <dict>
                    <key>Identifier</key>
                    <string>\(driveUUID)</string>
                    <key>ImageName</key>
                    <string>\(driveUUID).qcow2</string>
                    <key>ImageType</key>
                    <string>Disk</string>
                    <key>Interface</key>
                    <string>NVMe</string>
                    <key>InterfaceVersion</key>
                    <integer>1</integer>
                    <key>ReadOnly</key>
                    <false/>
                </dict>
            </array>
            <key>Network</key>
            <array>
                <dict>
                    <key>Hardware</key>
                    <string>virtio-net-pci</string>
                    <key>IsolateFromHost</key>
                    <false/>
                    <key>MacAddress</key>
                    <string>\(macAddr)</string>
                    <key>Mode</key>
                    <string>Emulated</string>
                    <key>PortForward</key>
                    <array/>
                </dict>
            </array>
            <key>Sound</key>
            <array>
                <dict>
                    <key>Hardware</key>
                    <string>intel-hda</string>
                </dict>
            </array>
            <key>Serial</key>
            <array/>
        </dict>
        </plist>
        """

        try plist.write(to: vmDir.appendingPathComponent("config.plist"),
                        atomically: true, encoding: .utf8)

        return vmDir
    }
}

// MARK: - Helpers

func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1 {
        return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_048_576
    return String(format: "%.0f MB", mb)
}
