import Darwin

enum TTYDetection {
    /// Returns true if stdout is connected to an interactive terminal.
    static var isTerminal: Bool {
        Darwin.isatty(STDOUT_FILENO) != 0
    }
}
