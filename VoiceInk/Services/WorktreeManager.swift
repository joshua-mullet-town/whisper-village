import Foundation
import AppKit

/// Manages git worktrees stored in ~/.worktrees/
@MainActor
class WorktreeManager: ObservableObject {
    static let shared = WorktreeManager()

    /// All discovered worktrees, grouped by project
    @Published var worktrees: [String: [Worktree]] = [:]

    /// Worktrees currently being deleted (for UI state)
    @Published var deletingWorktrees: Set<String> = []

    /// Whether we have any worktrees
    var hasWorktrees: Bool {
        !worktrees.isEmpty
    }

    /// Total count of all worktrees
    var totalCount: Int {
        worktrees.values.reduce(0) { $0 + $1.count }
    }

    private let worktreesDir: URL

    // File system watcher (nonisolated for thread safety)
    private let fileWatcher: WorktreeFileWatcher

    init() {
        worktreesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".worktrees")

        // Create file watcher
        fileWatcher = WorktreeFileWatcher(directory: worktreesDir)

        // Initial scan
        Task {
            await scan()
        }

        // Start watching for changes
        fileWatcher.startWatching { [weak self] in
            Task { @MainActor in
                await self?.scan()
            }
        }
    }

    /// Force a manual refresh
    func refresh() async {
        await scan()
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

    /// Delete a worktree (non-blocking, runs on background thread)
    func delete(_ worktree: Worktree) {
        // Mark as deleting for UI feedback
        deletingWorktrees.insert(worktree.id)

        // Run deletion on background thread to avoid blocking UI
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // First, remove the git worktree reference from the main repo
                if let mainRepoPath = worktree.mainRepoPath {
                    let mainRepo = URL(fileURLWithPath: mainRepoPath)
                    do {
                        _ = try await self?.runGitCommandBackground(["worktree", "remove", "--force", worktree.path.path], at: mainRepo)
                    } catch {
                        // If that fails, try to remove just the directory
                        print("WorktreeManager: git worktree remove failed, removing directory directly")
                    }

                    // Delete the branch
                    do {
                        _ = try await self?.runGitCommandBackground(["branch", "-D", worktree.branch], at: mainRepo)
                    } catch {
                        print("WorktreeManager: Could not delete branch \(worktree.branch)")
                    }
                }

                // Remove the directory (this is the slow part for large worktrees)
                try FileManager.default.removeItem(at: worktree.path)

                // Update UI on main thread
                await MainActor.run {
                    self?.deletingWorktrees.remove(worktree.id)
                    Task {
                        await self?.scan()
                    }
                }
            } catch {
                print("WorktreeManager: Error deleting worktree: \(error)")
                // Remove from deleting state even on error
                await MainActor.run {
                    self?.deletingWorktrees.remove(worktree.id)
                }
            }
        }
    }

    /// Check if a worktree is being deleted
    func isDeleting(_ worktree: Worktree) -> Bool {
        deletingWorktrees.contains(worktree.id)
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

    /// Run a git command and return the output (MainActor version)
    private func runGitCommand(_ arguments: [String], at directory: URL) async throws -> String {
        return try await runGitCommandBackground(arguments, at: directory)
    }

    /// Run a git command on background thread (safe to call from Task.detached)
    private nonisolated func runGitCommandBackground(_ arguments: [String], at directory: URL) async throws -> String {
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

// MARK: - File System Watcher

/// Watches ~/.worktrees/ and all project subdirectories for changes
/// Structure: ~/.worktrees/project/branch/ - need to watch both levels
final class WorktreeFileWatcher: @unchecked Sendable {
    private let rootDirectory: URL
    private var watchers: [(fd: Int32, source: DispatchSourceFileSystemObject)] = []
    private var onChange: (() -> Void)?
    private let lock = NSLock()
    private var debounceWorkItem: DispatchWorkItem?

    init(directory: URL) {
        self.rootDirectory = directory
    }

    deinit {
        stopWatching()
    }

    func startWatching(onChange: @escaping () -> Void) {
        self.onChange = onChange
        setupWatchers()
    }

    private func setupWatchers() {
        lock.lock()
        defer { lock.unlock() }

        // Stop existing watchers
        for watcher in watchers {
            watcher.source.cancel()
        }
        watchers.removeAll()

        let fm = FileManager.default

        // Create root directory if it doesn't exist
        if !fm.fileExists(atPath: rootDirectory.path) {
            try? fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }

        // Watch the root directory
        if let watcher = createWatcher(for: rootDirectory) {
            watchers.append(watcher)
        }

        // Watch each project directory (one level deep)
        if let projects = try? fm.contentsOfDirectory(atPath: rootDirectory.path) {
            for project in projects {
                if project.hasPrefix(".") { continue }
                let projectPath = rootDirectory.appendingPathComponent(project)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: projectPath.path, isDirectory: &isDir), isDir.boolValue {
                    if let watcher = createWatcher(for: projectPath) {
                        watchers.append(watcher)
                    }
                }
            }
        }
    }

    private func createWatcher(for directory: URL) -> (fd: Int32, source: DispatchSourceFileSystemObject)? {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            print("WorktreeFileWatcher: Could not open \(directory.path) for watching")
            return nil
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .link],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.handleChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        return (fd, source)
    }

    private func handleChange() {
        // Debounce multiple rapid changes
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            // Re-setup watchers in case new project directories were added
            self?.setupWatchers()
            self?.onChange?()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func stopWatching() {
        lock.lock()
        defer { lock.unlock() }
        for watcher in watchers {
            watcher.source.cancel()
        }
        watchers.removeAll()
    }
}
