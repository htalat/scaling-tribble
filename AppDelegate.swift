import Cocoa
import Darwin
import Combine

// MARK: - Main Application Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private let processManager = ProcessManager()
    private let repositoryManager = RepositoryManager()
    private lazy var preferencesManager = PreferencesManager(repositoryManager: repositoryManager)
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupMenuBar()
        observeProcessChanges()
    }
    
    // MARK: - Setup
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Git Repos")
            button.toolTip = "Git Repository Manager"
        }
        
        updateMenu()
    }
    
    private func observeProcessChanges() {
        // Observe changes to running processes and update menu
        processManager.$runningProcesses.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMenu()
            }
        }.store(in: &cancellables)
    }
    
    private var cancellables: Set<AnyCancellable> = []
    
    // MARK: - Menu Management
    
    private func updateMenu() {
        let menu = NSMenu()
        
        let repos = repositoryManager.getConfiguredRepositories()
        
        if repos.isEmpty {
            addEmptyStateItems(to: menu)
        } else {
            addRepositoryItems(repos, to: menu)
        }
        
        addControlItems(to: menu)
        statusItem?.menu = menu
    }
    
    private func addEmptyStateItems(to menu: NSMenu) {
        menu.addItem(NSMenuItem(title: "No repositories configured", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Edit repos.json to add repositories", action: nil, keyEquivalent: ""))
    }
    
    private func addRepositoryItems(_ repos: [ConfiguredRepo], to menu: NSMenu) {
        for repo in repos {
            let isRunning = processManager.runningProcesses[repo.path]?.isRunning == true
            let statusIcon = isRunning ? "🟢 " : ""
            
            // Repository name item
            let repoMenuItem = NSMenuItem(title: "\(statusIcon)\(repo.name) (\(repo.branch))", action: nil, keyEquivalent: "")
            repoMenuItem.isEnabled = false
            menu.addItem(repoMenuItem)
            
            // Open button
            let openItem = NSMenuItem(title: "  📂 Open", action: #selector(openRepository(_:)), keyEquivalent: "")
            openItem.representedObject = repo.path
            menu.addItem(openItem)
            
            // Start/Stop button
            if let startCommand = repo.startCommand, !startCommand.isEmpty {
                if isRunning {
                    let stopItem = NSMenuItem(title: "  ⏹️ Stop App", action: #selector(stopApp(_:)), keyEquivalent: "")
                    stopItem.representedObject = repo.path
                    menu.addItem(stopItem)
                } else {
                    let startItem = NSMenuItem(title: "  ▶️ Start App", action: #selector(startApp(_:)), keyEquivalent: "")
                    startItem.representedObject = repo.path
                    menu.addItem(startItem)
                }
            }
            
            // Description
            if let description = repo.description {
                let descItem = NSMenuItem(title: "  ℹ️ \(description)", action: nil, keyEquivalent: "")
                descItem.isEnabled = false
                menu.addItem(descItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
    }
    
    
    private func addControlItems(to menu: NSMenu) {
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshRepositories), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
    
    // MARK: - Actions
    
    @objc private func openRepository(_ sender: NSMenuItem) {
        guard let repoPath = sender.representedObject as? String else { return }
        repositoryManager.openRepository(path: repoPath)
    }
    
    @objc private func startApp(_ sender: NSMenuItem) {
        guard let repoPath = sender.representedObject as? String else {
            preferencesManager.showAlert(title: "Error", message: "No repository path provided")
            return
        }
        
        let command = repositoryManager.getStartCommand(for: repoPath)
        if command.isEmpty {
            preferencesManager.showAlert(title: "No Start Command", message: "No start command configured for this repository in repos.json.")
            return
        }
        
        processManager.startApp(repoPath: repoPath, command: command) { [weak self] success, message in
            if success {
                let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
                self?.preferencesManager.showAlert(title: "App Started", message: "\(repoName) is now running in Terminal. \(message)")
            } else {
                self?.preferencesManager.showAlert(title: "Start Failed", message: message)
            }
        }
    }
    
    @objc private func stopApp(_ sender: NSMenuItem) {
        guard let repoPath = sender.representedObject as? String else {
            preferencesManager.showAlert(title: "Error", message: "No repository path provided")
            return
        }
        
        processManager.stopApp(repoPath: repoPath) { [weak self] success, message in
            let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
            let title = success ? "App Stopped" : "Stop Failed"
            let fullMessage = success ? "\(repoName) has been stopped. \(message)" : message
            self?.preferencesManager.showAlert(title: title, message: fullMessage)
        }
    }
    
    @objc private func refreshRepositories() {
        updateMenu()
    }
    
    @objc private func openPreferences() {
        preferencesManager.showPreferences()
    }
}