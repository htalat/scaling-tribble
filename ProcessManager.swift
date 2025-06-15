import Foundation
import Darwin
import Cocoa
import Combine

// MARK: - Process Management

class ProcessManager: ObservableObject {
    @Published var runningProcesses: [String: RunningProcess] = [:]
    private var pidCheckTimer: Timer?
    
    init() {
        startPidMonitoring()
    }
    
    deinit {
        pidCheckTimer?.invalidate()
    }
    
    // MARK: - Monitoring
    
    func startPidMonitoring() {
        pidCheckTimer?.invalidate()
        pidCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkRunningProcesses()
        }
        RunLoop.main.add(pidCheckTimer!, forMode: .common)
    }
    
    func checkRunningProcesses() {
        var processesToRemove: [String] = []
        
        for (repoPath, runningProcess) in runningProcesses {
            if runningProcess.pid > 0 {
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
            }
        }
    }
    
    func isProcessRunning(pid: Int32) -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var size = MemoryLayout<kinfo_proc>.stride
        
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        return result == 0 && size > 0
    }
    
    // MARK: - Process Control
    
    func startApp(repoPath: String, command: String, completion: @escaping (Bool, String) -> Void) {
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        print("Starting app for repository: \(repoName)")
        print("Command: \(command)")
        
        let processId = UUID().uuidString
        let markerFile = "/tmp/center_process_\(processId)"
        
        // Immediately mark as running
        let initialProcess = RunningProcess(repoPath: repoPath, pid: -1, command: command, isRunning: true)
        self.runningProcesses[repoPath] = initialProcess
        
        // Create wrapper script
        let wrapperScript = createWrapperScript(repoPath: repoPath, command: command, markerFile: markerFile)
        let wrapperFile = "/tmp/center_wrapper_\(processId).sh"
        
        do {
            try wrapperScript.write(to: URL(fileURLWithPath: wrapperFile), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperFile)
            
            executeInTerminal(wrapperFile: wrapperFile) { [weak self] success, error in
                if success {
                    // Wait for PID file
                    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3.0) {
                        if let pid = self?.getProcessPid(markerFile: markerFile) {
                            print("Found process with PID: \(pid)")
                            DispatchQueue.main.async {
                                let runningProcess = RunningProcess(repoPath: repoPath, pid: pid, command: command, isRunning: true)
                                self?.runningProcesses[repoPath] = runningProcess
                                completion(true, "Started with PID: \(pid)")
                            }
                        } else {
                            completion(true, "Started (PID not captured)")
                        }
                    }
                } else {
                    self?.runningProcesses.removeValue(forKey: repoPath)
                    completion(false, error)
                }
            }
        } catch {
            self.runningProcesses.removeValue(forKey: repoPath)
            completion(false, "Failed to create wrapper script: \(error)")
        }
    }
    
    func stopApp(repoPath: String, completion: @escaping (Bool, String) -> Void) {
        guard let runningProcess = runningProcesses[repoPath] else {
            completion(false, "No running process found")
            return
        }
        
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        print("Stopping app for repository: \(repoName)")
        
        if runningProcess.pid > 0 {
            killProcessTree(pid: runningProcess.pid)
            DispatchQueue.main.async {
                self.runningProcesses.removeValue(forKey: repoPath)
                completion(true, "Terminated process \(runningProcess.pid)")
            }
        } else {
            // Fallback
            let killCommand = "pkill -f \"node.*\(repoPath)\" || pkill -f \"\(runningProcess.command)\""
            executeCommand(killCommand) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.runningProcesses.removeValue(forKey: repoPath)
                    completion(true, "Attempted to stop related processes")
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createWrapperScript(repoPath: String, command: String, markerFile: String) -> String {
        return """
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
    }
    
    private func executeInTerminal(wrapperFile: String, completion: @escaping (Bool, String) -> Void) {
        let script = """
        tell application "Terminal"
            do script "'\(wrapperFile)'; rm -f '\(wrapperFile)'"
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            completion(false, "Failed to open Terminal: \(error)")
        } else {
            completion(true, "")
        }
    }
    
    private func executeCommand(_ command: String, completion: @escaping (String) -> Void) {
        let script = """
        tell application "Terminal"
            do script "\(command)"
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
        completion("")
    }
    
    private func killProcessTree(pid: Int32) {
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
    
    private func getProcessPid(markerFile: String) -> Int32? {
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
}