import Foundation

public final class DataStore {
    private let fileManager = FileManager.default
    public let baseDirectory: URL
    public let dataFileURL: URL

    /// Callback fired when data.json is modified by an external process.
    /// Called on the main queue after debouncing. Not fired for self-writes.
    public var onExternalChange: (() -> Void)?

    /// Set to true during save operations to suppress self-triggered file watcher events.
    private var isWriting = false

    /// File watching state
    private var directoryFileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.3

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("Arcmark", isDirectory: true)
        }
        self.dataFileURL = self.baseDirectory.appendingPathComponent("data.json")
    }

    deinit {
        stopWatching()
    }

    public func load() -> AppState {
        ensureDirectories()
        guard fileManager.fileExists(atPath: dataFileURL.path) else {
            let defaultState = Self.defaultState()
            save(defaultState)
            return defaultState
        }

        do {
            let data = try Data(contentsOf: dataFileURL)
            let decoder = JSONDecoder()
            let state = try decoder.decode(AppState.self, from: data)
            return state
        } catch {
            let fallback = Self.defaultState()
            save(fallback)
            return fallback
        }
    }

    public func save(_ state: AppState) {
        ensureDirectories()
        isWriting = true
        defer { isWriting = false }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: dataFileURL, options: [.atomic])
        } catch {
            // Failing silently to avoid crashing; this can be surfaced later in a UI.
        }
    }

    // MARK: - Throwing Variants (CLI)

    /// Load state, propagating errors instead of silently falling back to defaults.
    /// Use this in CLI contexts where silent data loss is unacceptable.
    public func tryLoad() throws -> AppState {
        try tryEnsureDirectories()
        guard fileManager.fileExists(atPath: dataFileURL.path) else {
            let defaultState = Self.defaultState()
            try trySave(defaultState)
            return defaultState
        }

        let data = try Data(contentsOf: dataFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(AppState.self, from: data)
    }

    /// Save state, propagating errors instead of silently swallowing them.
    /// Use this in CLI contexts where failed writes must produce non-zero exit codes.
    public func trySave(_ state: AppState) throws {
        try tryEnsureDirectories()
        isWriting = true
        defer { isWriting = false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: dataFileURL, options: [.atomic])
    }

    // MARK: - File Watching

    /// Start monitoring data.json for external changes. Call from GUI context only.
    public func startWatching() {
        ensureDirectories()

        let fd = open(baseDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            if self.isWriting { return }

            // Debounce: cancel previous pending reload, schedule new one
            self.debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.isWriting { return }
                self.onExternalChange?()
            }
            self.debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        dispatchSource = source
        source.resume()
    }

    /// Stop monitoring for file changes.
    public func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        dispatchSource?.cancel()
        dispatchSource = nil
        directoryFileDescriptor = -1
    }

    // MARK: - Icons

    public func iconsDirectory() -> URL {
        let iconsURL = baseDirectory.appendingPathComponent("Icons", isDirectory: true)
        if !fileManager.fileExists(atPath: iconsURL.path) {
            try? fileManager.createDirectory(at: iconsURL, withIntermediateDirectories: true)
        }
        return iconsURL
    }

    private func tryEnsureDirectories() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func ensureDirectories() {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    public static func defaultState() -> AppState {
        let workspace = Workspace(
            id: UUID(),
            name: "Inbox",
            colorId: .defaultColor(),
            items: []
        )
        return AppState(schemaVersion: 1, workspaces: [workspace], selectedWorkspaceId: workspace.id, isSettingsSelected: false)
    }
}
