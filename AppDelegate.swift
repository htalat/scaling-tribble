import Cocoa
import Foundation
import Darwin

struct ConfiguredRepo: Codable {
    let name: String
    let path: String
    let startCommand: String?
    let stopCommand: String?
    let description: String?
    
    var branch: String {
        let process = Process()
        process.currentDirectoryPath = path
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["branch", "--show-current"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            return output.isEmpty ? "unknown" : output
        } catch {
            return "unknown"
        }
    }
}

struct RepoConfig: Codable {
    let repositories: [ConfiguredRepo]
}

struct GitRepo {
    let name: String
    let path: String
    let branch: String
}

struct RunningProcess {
    let repoPath: String
    let pid: Int32
    let command: String
    var isRunning: Bool
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var preferencesWindow: NSWindow?
    var runningProcesses: [String: RunningProcess] = [:]
    var pidCheckTimer: Timer?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupDefaultDirectory()
        setupMenuBar()
        startPidMonitoring()
    }
    
func startPidMonitoring() {
    pidCheckTimer?.invalidate()
    pidCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        self?.checkRunningProcesses()
    }
    RunLoop.main.add(pidCheckTimer!, forMode: .common)
}

    
    func setupDefaultDirectory() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "developerDirectory") == nil {
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            let defaultPath = homeDirectory.appendingPathComponent("Developer").path
            defaults.set(defaultPath, forKey: "developerDirectory")
        }
        if defaults.string(forKey: "defaultEditor") == nil {
            defaults.set("VS Code", forKey: "defaultEditor")
        }
        if defaults.string(forKey: "configFilePath") == nil {
            let currentDirectory = FileManager.default.currentDirectoryPath
            let defaultConfigPath = URL(fileURLWithPath: currentDirectory).appendingPathComponent("repos.json").path
            defaults.set(defaultConfigPath, forKey: "configFilePath")
        }
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Git Repos")
            button.toolTip = "Git Repository Manager"
        }
        
        updateMenu()
    }
    
    func updateMenu() {
        let menu = NSMenu()
        
        let repos = getConfiguredRepositories()
        
        if repos.isEmpty {
            menu.addItem(NSMenuItem(title: "No repositories configured", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Edit repos.json to add repositories", action: nil, keyEquivalent: ""))
        } else {
            for repo in repos {
                let isRunning = runningProcesses[repo.path]?.isRunning == true
                let statusIcon = isRunning ? "🟢 " : ""
                let repoMenuItem = NSMenuItem(title: "\(statusIcon)\(repo.name) (\(repo.branch))", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                
                let openItem = NSMenuItem(title: "Open", action: #selector(openRepository(_:)), keyEquivalent: "")
                openItem.representedObject = repo.path
                openItem.isEnabled = true
                submenu.addItem(openItem)
                
                submenu.addItem(NSMenuItem.separator())
                
                if let startCommand = repo.startCommand, !startCommand.isEmpty {
                    if isRunning {
                        let stopItem = NSMenuItem(title: "Stop App", action: #selector(stopApp(_:)), keyEquivalent: "")
                        stopItem.representedObject = repo.path
                        stopItem.isEnabled = true
                        submenu.addItem(stopItem)
                    } else {
                        let startItem = NSMenuItem(title: "Start App", action: #selector(startApp(_:)), keyEquivalent: "")
                        startItem.representedObject = repo.path
                        startItem.isEnabled = true
                        submenu.addItem(startItem)
                    }
                }
                
                if let description = repo.description {
                    let descItem = NSMenuItem(title: description, action: nil, keyEquivalent: "")
                    descItem.isEnabled = false
                    submenu.addItem(descItem)
                }
                
                repoMenuItem.submenu = submenu
                menu.addItem(repoMenuItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshRepositories), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    func getConfiguredRepositories() -> [ConfiguredRepo] {
        let defaults = UserDefaults.standard
        guard let configPath = defaults.string(forKey: "configFilePath") else {
            return []
        }
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else {
            return []
        }
        
        do {
            let config = try JSONDecoder().decode(RepoConfig.self, from: data)
            return config.repositories.filter { repo in
                FileManager.default.fileExists(atPath: repo.path)
            }
        } catch {
            print("Error parsing config file: \(error)")
            return []
        }
    }
    
    func getCurrentBranch(at path: String) -> String {
        let process = Process()
        process.currentDirectoryPath = path
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["branch", "--show-current"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            return output.isEmpty ? "unknown" : output
        } catch {
            return "unknown"
        }
    }
    
    @objc func openRepository(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let defaults = UserDefaults.standard
        let editor = defaults.string(forKey: "defaultEditor") ?? "VS Code"
        
        switch editor {
        case "VS Code":
            openInVSCode(path: path)
        case "Finder":
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case "Terminal":
            openInTerminal(path: path)
        default:
            openInVSCode(path: path)
        }
    }
    
    func openInVSCode(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/code")
        process.arguments = [path]
        
        do {
            try process.run()
        } catch {
            let altProcess = Process()
            altProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/code")
            altProcess.arguments = [path]
            
            do {
                try altProcess.run()
            } catch {
                let workspace = NSWorkspace.shared
                if let vscodeApp = workspace.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
                    workspace.open([URL(fileURLWithPath: path)], withApplicationAt: vscodeApp, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            }
        }
    }
    
    func openInTerminal(path: String) {
        let script = "tell application \"Terminal\" to do script \"cd '\(path)'\""
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
    }
    
    @objc func refreshRepositories() {
        updateMenu()
    }
    
    @objc func openPreferences() {
        if preferencesWindow == nil {
            createPreferencesWindow()
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func createPreferencesWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                             styleMask: [.titled, .closable],
                             backing: .buffered,
                             defer: false)
        window.title = "Preferences"
        window.center()
        
        let contentView = NSView(frame: window.contentView!.bounds)
        
        let directoryLabel = NSTextField(labelWithString: "Developer Directory:")
        directoryLabel.frame = NSRect(x: 20, y: 130, width: 150, height: 20)
        contentView.addSubview(directoryLabel)
        
        let textField = NSTextField(frame: NSRect(x: 20, y: 100, width: 280, height: 20))
        let defaults = UserDefaults.standard
        textField.stringValue = defaults.string(forKey: "developerDirectory") ?? ""
        textField.target = self
        textField.action = #selector(directoryChanged(_:))
        contentView.addSubview(textField)
        
        let browseButton = NSButton(frame: NSRect(x: 310, y: 95, width: 70, height: 30))
        browseButton.title = "Browse"
        browseButton.target = self
        browseButton.action = #selector(browseDirectory(_:))
        contentView.addSubview(browseButton)
        
        let editorLabel = NSTextField(labelWithString: "Default Editor:")
        editorLabel.frame = NSRect(x: 20, y: 60, width: 150, height: 20)
        contentView.addSubview(editorLabel)
        
        let editorPopup = NSPopUpButton(frame: NSRect(x: 20, y: 30, width: 150, height: 25))
        editorPopup.addItems(withTitles: ["VS Code", "Finder", "Terminal"])
        let selectedEditor = defaults.string(forKey: "defaultEditor") ?? "VS Code"
        editorPopup.selectItem(withTitle: selectedEditor)
        editorPopup.target = self
        editorPopup.action = #selector(editorChanged(_:))
        contentView.addSubview(editorPopup)
        
        let configLabel = NSTextField(labelWithString: "Config File:")
        configLabel.frame = NSRect(x: 200, y: 60, width: 100, height: 20)
        contentView.addSubview(configLabel)
        
        let configButton = NSButton(frame: NSRect(x: 200, y: 30, width: 150, height: 25))
        configButton.title = "Edit repos.json"
        configButton.target = self
        configButton.action = #selector(editConfigFile(_:))
        contentView.addSubview(configButton)
        
        window.contentView = contentView
        preferencesWindow = window
    }
    
    @objc func directoryChanged(_ sender: NSTextField) {
        let defaults = UserDefaults.standard
        defaults.set(sender.stringValue, forKey: "developerDirectory")
        updateMenu()
    }
    
    @objc func browseDirectory(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                let defaults = UserDefaults.standard
                defaults.set(url.path, forKey: "developerDirectory")
                
                if let textField = preferencesWindow?.contentView?.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }) {
                    textField.stringValue = url.path
                }
                
                updateMenu()
            }
        }
    }
    
    @objc func editorChanged(_ sender: NSPopUpButton) {
        let defaults = UserDefaults.standard
        defaults.set(sender.titleOfSelectedItem, forKey: "defaultEditor")
    }
    
    @objc func editConfigFile(_ sender: NSButton) {
        let defaults = UserDefaults.standard
        guard let configPath = defaults.string(forKey: "configFilePath") else { return }
        
        let defaults2 = UserDefaults.standard
        let editor = defaults2.string(forKey: "defaultEditor") ?? "VS Code"
        
        switch editor {
        case "VS Code":
            openInVSCode(path: configPath)
        case "Finder":
            NSWorkspace.shared.selectFile(configPath, inFileViewerRootedAtPath: "")
        case "Terminal":
            let dir = URL(fileURLWithPath: configPath).deletingLastPathComponent().path
            openInTerminal(path: dir)
        default:
            openInVSCode(path: configPath)
        }
    }
    
@objc func startApp(_ sender: NSMenuItem) {
    guard let repoPath = sender.representedObject as? String else {
        print("Error: No repository path provided")
        return
    }
    
    let command = getStartCommand(for: repoPath)
    if command.isEmpty {
        showCommandAlert(title: "No Start Command", message: "No start command configured for this repository in repos.json.")
        return
    }
    
    let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
    print("Starting app for repository: \(repoName)")
    print("Command: \(command)")
    
    // Create a unique identifier for this process
    let processId = UUID().uuidString
    let markerFile = "/tmp/center_process_\(processId)"
    
    // Immediately mark as running
    let initialProcess = RunningProcess(repoPath: repoPath, pid: -1, command: command, isRunning: true)
    self.runningProcesses[repoPath] = initialProcess
    self.updateMenu()
    
    // Create a wrapper script that will help us track the actual node process
    let wrapperScript = """
    #!/bin/bash
    cd "\(repoPath)"
    
    # Start the command in the background and get its PID
    \(command) &
    APP_PID=$!
    
    # Wait a moment for any child processes to spawn
    sleep 2
    
    # Find the actual node process
    if pgrep -P $APP_PID > /dev/null; then
        # If there are child processes, find the node/npm process
        REAL_PID=$(pgrep -f "node.*\(repoPath)" | tail -n 1)
    else
        REAL_PID=$APP_PID
    fi
    
    # Write the real PID to the marker file
    echo $REAL_PID > "\(markerFile)"
    
    # Wait for the original process to finish
    wait $APP_PID
    
    # Clean up
    rm -f "\(markerFile)"
    """
    
    // Write the wrapper script to a temporary file
    let wrapperFile = "/tmp/center_wrapper_\(processId).sh"
    do {
        try wrapperScript.write(to: URL(fileURLWithPath: wrapperFile), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperFile)
        
        // Execute the wrapper script in Terminal
        let script = """
        tell application "Terminal"
            do script "'\(wrapperFile)'; rm -f '\(wrapperFile)'"
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            print("Failed to execute AppleScript: \(error)")
            self.runningProcesses.removeValue(forKey: repoPath)
            self.updateMenu()
            showCommandAlert(title: "Start Failed", message: "Failed to open Terminal: \(error)")
        } else {
            print("Terminal command executed successfully")
            
            // Wait a moment for the process to start and PID file to be written
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3.0) {
                if let pid = self.getProcessPid(markerFile: markerFile) {
                    print("Found process with PID: \(pid)")
                    DispatchQueue.main.async {
                        let runningProcess = RunningProcess(repoPath: repoPath, pid: pid, command: command, isRunning: true)
                        self.runningProcesses[repoPath] = runningProcess
                        self.updateMenu()
                    }
                }
            }
        }
    } catch {
        print("Failed to create wrapper script: \(error)")
        self.runningProcesses.removeValue(forKey: repoPath)
        self.updateMenu()
        showCommandAlert(title: "Start Failed", message: "Failed to create wrapper script: \(error)")
    }
}

func getProcessPid(markerFile: String) -> Int32? {
    do {
        if FileManager.default.fileExists(atPath: markerFile) {
            let pidString = try String(contentsOfFile: markerFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let pid = Int32(pidString) {
                return pid
            }
        }
    } catch {
        print("Error reading PID file: \(error)")
    }
    return nil
}

// Update the process checking method
func checkRunningProcesses() {
    var processesToRemove: [String] = []
    
    for (repoPath, runningProcess) in runningProcesses {
        if runningProcess.pid > 0 {
            // Check if the process is still running
            if !isProcessRunning(pid: runningProcess.pid) {
                processesToRemove.append(repoPath)
                print("Process \(runningProcess.pid) is no longer running")
            }
        }
    }
    
    if !processesToRemove.isEmpty {
        DispatchQueue.main.async {
            for repoPath in processesToRemove {
                self.runningProcesses.removeValue(forKey: repoPath)
            }
            self.updateMenu()
        }
    }
}

// Update the process running check method
func isProcessRunning(pid: Int32) -> Bool {
    var info = kinfo_proc()
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var size = MemoryLayout<kinfo_proc>.stride
    
    let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
    return result == 0 && size > 0
} 
// Update the stop app method to handle node processes better
@objc func stopApp(_ sender: NSMenuItem) {
    guard let repoPath = sender.representedObject as? String else {
        print("Error: No repository path provided")
        return
    }
    
    guard let runningProcess = runningProcesses[repoPath] else {
        print("Error: No running process found for path: \(repoPath)")
        return
    }
    
    let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
    print("Stopping app for repository: \(repoName)")
    
    // Function to kill process tree
    func killProcessTree(pid: Int32) {
        let script = """
        #!/bin/bash
        function kill_tree() {
            local pid=$1
            for child in $(pgrep -P $pid); do
                kill_tree $child
            done
            kill -TERM $pid 2>/dev/null || kill -KILL $pid 2>/dev/null
        }
        kill_tree \(pid)
        """
        
        let killScript = "/tmp/center_kill_\(UUID().uuidString).sh"
        do {
            try script.write(to: URL(fileURLWithPath: killScript), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: killScript)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: killScript)
            try process.run()
            process.waitUntilExit()
            
            try FileManager.default.removeItem(atPath: killScript)
        } catch {
            print("Error killing process tree: \(error)")
        }
    }
    
    if runningProcess.pid > 0 {
        // Kill the entire process tree
        killProcessTree(pid: runningProcess.pid)
        
        DispatchQueue.main.async {
            self.runningProcesses.removeValue(forKey: repoPath)
            self.updateMenu()
        }
    } else {
        // Fallback: try to kill any matching processes
        let killCommand = """
        pkill -f "node.*\(repoPath)" || pkill -f "\(runningProcess.command)"
        """
        
        let script = """
        tell application "Terminal"
            do script "\(killCommand)"
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
        
        DispatchQueue.main.async {
            self.runningProcesses.removeValue(forKey: repoPath)
            self.updateMenu()
            self.showCommandAlert(title: "Process Tracked Stopped", 
                               message: "Attempted to stop \(repoName) and related processes")
        }
    }
}
    
    // Update the process finding method
    func findProcessPid(repoPath: String, command: String) -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty,
            let pid = Int32(output) {
                return pid
            }
        } catch {
            print("Error finding process: \(error)")
        }
        
        return nil
    }
    
    @objc func configureCommand(_ sender: NSMenuItem) {
        showCommandAlert(title: "Configuration", message: "Commands are now configured in repos.json file. Edit the JSON file to modify start/stop commands for repositories.")
    }
    
    func getStartCommand(for repoPath: String) -> String {
        let repos = getConfiguredRepositories()
        for repo in repos {
            if repo.path == repoPath {
                return repo.startCommand ?? ""
            }
        }
        return ""
    }
    
    
    func showCommandAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
    
}