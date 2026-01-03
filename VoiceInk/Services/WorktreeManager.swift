import Foundation
import AppKit

/// Manages git worktrees stored in ~/.worktrees/
@MainActor
class WorktreeManager: ObservableObject {
    static let shared = WorktreeManager()

    /// All discovered worktrees, grouped by project
    @Published var worktrees: [String: [Worktree]] = [:]

    /// Whether we have any worktrees
    var hasWorktrees: Bool {
        !worktrees.isEmpty
    }

    /// Total count of all worktrees
    var totalCount: Int {
        worktrees.values.reduce(0) { $0 + $1.count }
    }

    private let worktreesDir: URL

    init() {
        worktreesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".worktrees")

        // Initial scan
        Task {
            await scan()
        }
    }

    /// Scan ~/.worktrees/ for all worktrees
    func scan() async {
        var discovered: [String: [Worktree]] = [:]

        let fm = FileManager.default

        // Check if worktrees directory exists
        guard fm.fileExists(atPath: worktreesDir.path) else {
            worktrees = [:]
            return
        }

        do {
            // List project directories
            let projects = try fm.contentsOfDirectory(atPath: worktreesDir.path)

            for project in projects {
                // Skip hidden files
                if project.hasPrefix(".") { continue }

                let projectPath = worktreesDir.appendingPathComponent(project)

                // Check it's a directory
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: projectPath.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                // List worktrees in this project
                let branches = try fm.contentsOfDirectory(atPath: projectPath.path)

                for branch in branches {
                    if branch.hasPrefix(".") { continue }

                    let worktreePath = projectPath.appendingPathComponent(branch)

                    var isWorktreeDir: ObjCBool = false
                    guard fm.fileExists(atPath: worktreePath.path, isDirectory: &isWorktreeDir), isWorktreeDir.boolValue else {
                        continue
                    }

                    // Read metadata if available
                    let metaPath = worktreePath.appendingPathComponent(".worktree-meta.json")
                    var metadata: WorktreeMetadata?

                    if fm.fileExists(atPath: metaPath.path),
                       let data = try? Data(contentsOf: metaPath),
                       let meta = try? JSONDecoder().decode(WorktreeMetadata.self, from: data) {
                        metadata = meta
                    }

                    // Check git status (clean/dirty)
                    let status = await checkGitStatus(at: worktreePath)

                    let worktree = Worktree(
                        id: "\(project)/\(branch)",
                        project: project,
                        branch: metadata?.branch ?? branch,  // Use the actual branch name from metadata or directory
                        directoryName: branch,
                        path: worktreePath,
                        mainRepoPath: metadata?.mainRepoPath,
                        baseBranch: metadata?.baseBranch,
                        created: metadata?.created,
                        status: status
                    )

                    if discovered[project] == nil {
                        discovered[project] = []
                    }
                    discovered[project]?.append(worktree)
                }
            }
        } catch {
            print("WorktreeManager: Error scanning worktrees: \(error)")
        }

        worktrees = discovered
    }

    /// Check if a worktree has uncommitted changes
    private func checkGitStatus(at path: URL) async -> WorktreeStatus {
        do {
            // Check for uncommitted changes
            let result = try await runGitCommand(["status", "--porcelain"], at: path)
            if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .clean
            } else {
                return .dirty
            }
        } catch {
            return .error
        }
    }

    /// Delete a worktree
    func delete(_ worktree: Worktree) async throws {
        // First, remove the git worktree reference from the main repo
        if let mainRepoPath = worktree.mainRepoPath {
            let mainRepo = URL(fileURLWithPath: mainRepoPath)
            do {
                _ = try await runGitCommand(["worktree", "remove", "--force", worktree.path.path], at: mainRepo)
            } catch {
                // If that fails, try to remove just the directory
                print("WorktreeManager: git worktree remove failed, removing directory directly")
            }

            // Delete the branch
            do {
                _ = try await runGitCommand(["branch", "-D", worktree.branch], at: mainRepo)
            } catch {
                print("WorktreeManager: Could not delete branch \(worktree.branch)")
            }
        }

        // Remove the directory
        try FileManager.default.removeItem(at: worktree.path)

        // Rescan
        await scan()
    }

    /// Copy the cd command to clipboard
    func copyPath(_ worktree: Worktree) {
        let command = "cd \(worktree.path.path)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }
    
    /// Open worktree in VS Code
    func openInVSCode(_ worktree: Worktree) {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Visual Studio Code", worktree.path.path]
        
        do {
            try task.run()
        } catch {
            print("Failed to open in VS Code: \(error)")
        }
    }

    /// Open worktree in Finder
    func openInFinder(_ worktree: Worktree) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path.path)
    }

    /// Run a git command and return the output
    private func runGitCommand(_ arguments: [String], at directory: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            task.arguments = arguments
            task.currentDirectoryURL = directory

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if task.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "WorktreeManager",
                        code: Int(task.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: output]
                    ))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Data Models

struct Worktree: Identifiable {
    let id: String
    let project: String
    let branch: String
    let directoryName: String
    let path: URL
    let mainRepoPath: String?
    let baseBranch: String?
    let created: Date?
    let status: WorktreeStatus
}

enum WorktreeStatus {
    case clean
    case dirty
    case error

    var icon: String {
        switch self {
        case .clean: return "🟢"
        case .dirty: return "🟡"
        case .error: return "🔴"
        }
    }

    var color: String {
        switch self {
        case .clean: return "green"
        case .dirty: return "yellow"
        case .error: return "red"
        }
    }
}

struct WorktreeMetadata: Codable {
    let project: String
    let branch: String
    let baseBranch: String?
    let mainRepoPath: String?
    let created: Date?
}
