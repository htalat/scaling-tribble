import Cocoa
import Foundation

struct GitRepo {
    let name: String
    let path: String
    let branch: String
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var preferencesWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupDefaultDirectory()
        setupMenuBar()
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
        
        let repos = getGitRepositories()
        
        if repos.isEmpty {
            menu.addItem(NSMenuItem(title: "No Git repositories found", action: nil, keyEquivalent: ""))
        } else {
            for repo in repos {
                let menuItem = NSMenuItem(title: "\(repo.name) (\(repo.branch))", action: #selector(openRepository(_:)), keyEquivalent: "")
                menuItem.representedObject = repo.path
                menu.addItem(menuItem)
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
    
    func getGitRepositories() -> [GitRepo] {
        let defaults = UserDefaults.standard
        guard let developerPath = defaults.string(forKey: "developerDirectory") else {
            return []
        }
        
        let fileManager = FileManager.default
        let developerURL = URL(fileURLWithPath: developerPath)
        
        guard let contents = try? fileManager.contentsOfDirectory(at: developerURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        
        var repositories: [GitRepo] = []
        
        for url in contents {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                let gitPath = url.appendingPathComponent(".git")
                if fileManager.fileExists(atPath: gitPath.path) {
                    let repoName = url.lastPathComponent
                    let branch = getCurrentBranch(at: url.path)
                    repositories.append(GitRepo(name: repoName, path: url.path, branch: branch))
                }
            }
        }
        
        return repositories.sorted { $0.name.lowercased() < $1.name.lowercased() }
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
    
}