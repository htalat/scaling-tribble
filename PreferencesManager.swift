import Cocoa

// MARK: - Preferences Management

class PreferencesManager {
    private let repositoryManager: RepositoryManager
    private var preferencesWindow: NSWindow?
    
    init(repositoryManager: RepositoryManager) {
        self.repositoryManager = repositoryManager
    }
    
    // MARK: - Window Management
    
    func showPreferences() {
        if preferencesWindow == nil {
            createPreferencesWindow()
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func createPreferencesWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        
        let contentView = NSView(frame: window.contentView!.bounds)
        
        setupDirectoryControls(in: contentView)
        setupEditorControls(in: contentView)
        setupConfigControls(in: contentView)
        
        window.contentView = contentView
        preferencesWindow = window
    }
    
    // MARK: - Control Setup
    
    private func setupDirectoryControls(in contentView: NSView) {
        let directoryLabel = NSTextField(labelWithString: "Developer Directory:")
        directoryLabel.frame = NSRect(x: 20, y: 130, width: 150, height: 20)
        contentView.addSubview(directoryLabel)
        
        let textField = NSTextField(frame: NSRect(x: 20, y: 100, width: 280, height: 20))
        textField.stringValue = repositoryManager.developerDirectory
        textField.target = self
        textField.action = #selector(directoryChanged(_:))
        contentView.addSubview(textField)
        
        let browseButton = NSButton(frame: NSRect(x: 310, y: 95, width: 70, height: 30))
        browseButton.title = "Browse"
        browseButton.target = self
        browseButton.action = #selector(browseDirectory(_:))
        contentView.addSubview(browseButton)
    }
    
    private func setupEditorControls(in contentView: NSView) {
        let editorLabel = NSTextField(labelWithString: "Default Editor:")
        editorLabel.frame = NSRect(x: 20, y: 60, width: 150, height: 20)
        contentView.addSubview(editorLabel)
        
        let editorPopup = NSPopUpButton(frame: NSRect(x: 20, y: 30, width: 150, height: 25))
        editorPopup.addItems(withTitles: ["VS Code", "Finder", "Terminal"])
        editorPopup.selectItem(withTitle: repositoryManager.defaultEditor)
        editorPopup.target = self
        editorPopup.action = #selector(editorChanged(_:))
        contentView.addSubview(editorPopup)
    }
    
    private func setupConfigControls(in contentView: NSView) {
        let configLabel = NSTextField(labelWithString: "Config File:")
        configLabel.frame = NSRect(x: 200, y: 60, width: 100, height: 20)
        contentView.addSubview(configLabel)
        
        let configButton = NSButton(frame: NSRect(x: 200, y: 30, width: 150, height: 25))
        configButton.title = "Edit repos.json"
        configButton.target = self
        configButton.action = #selector(editConfigFile(_:))
        contentView.addSubview(configButton)
    }
    
    // MARK: - Actions
    
    @objc private func directoryChanged(_ sender: NSTextField) {
        repositoryManager.developerDirectory = sender.stringValue
    }
    
    @objc private func browseDirectory(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                repositoryManager.developerDirectory = url.path
                
                // Update the text field
                if let textField = preferencesWindow?.contentView?.subviews
                    .compactMap({ $0 as? NSTextField })
                    .first(where: { $0.isEditable }) {
                    textField.stringValue = url.path
                }
            }
        }
    }
    
    @objc private func editorChanged(_ sender: NSPopUpButton) {
        if let selectedTitle = sender.titleOfSelectedItem {
            repositoryManager.defaultEditor = selectedTitle
        }
    }
    
    @objc private func editConfigFile(_ sender: NSButton) {
        repositoryManager.openConfigFile()
    }
    
    // MARK: - Utilities
    
    func showAlert(title: String, message: String) {
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