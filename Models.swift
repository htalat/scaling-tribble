import Foundation

// MARK: - Repository Models

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

// MARK: - Process Models

struct RunningProcess {
    let repoPath: String
    let pid: Int32
    let command: String
    var isRunning: Bool
}

// MARK: - Legacy Models (for compatibility)

struct GitRepo {
    let name: String
    let path: String
    let branch: String
}