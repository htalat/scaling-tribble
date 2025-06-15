import Foundation
import Cocoa

// MARK: - Repository Management

class RepositoryManager {
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Configuration
    
    var configFilePath: String {
        if let path = userDefaults.string(forKey: "configFilePath") {
            return path
        }
        
        // Set default path
        let currentDirectory = FileManager.default.currentDirectoryPath
        let defaultPath = URL(fileURLWithPath: currentDirectory).appendingPathComponent("repos.json").path
        userDefaults.set(defaultPath, forKey: "configFilePath")
        return defaultPath
    }
    
    // MARK: - Repository Loading
    
    func getConfiguredRepositories() -> [ConfiguredRepo] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)) else {
            print("Could not read config file at: \(configFilePath)")
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
    
    func getStartCommand(for repoPath: String) -> String {
        let repos = getConfiguredRepositories()
        for repo in repos {
            if repo.path == repoPath {
                return repo.startCommand ?? ""
            }
        }
        return ""
    }
    
    // MARK: - Editor Management
    
    var defaultEditor: String {
        get {
            return userDefaults.string(forKey: "defaultEditor") ?? "VS Code"
        }
        set {
            userDefaults.set(newValue, forKey: "defaultEditor")
        }
    }
    
    var developerDirectory: String {
        get {
            if let path = userDefaults.string(forKey: "developerDirectory") {
                return path
            }
            
            // Set default path
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            let defaultPath = homeDirectory.appendingPathComponent("Developer").path
            userDefaults.set(defaultPath, forKey: "developerDirectory")
            return defaultPath
        }
        set {
            userDefaults.set(newValue, forKey: "developerDirectory")
        }
    }
    
    // MARK: - Editor Operations
    
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
    
    func openRepository(path: String) {
        switch defaultEditor {
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
    
    func openConfigFile() {
        switch defaultEditor {
        case "VS Code":
            openInVSCode(path: configFilePath)
        case "Finder":
            NSWorkspace.shared.selectFile(configFilePath, inFileViewerRootedAtPath: "")
        case "Terminal":
            let dir = URL(fileURLWithPath: configFilePath).deletingLastPathComponent().path
            openInTerminal(path: dir)
        default:
            openInVSCode(path: configFilePath)
        }
    }
}