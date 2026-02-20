import AppKit
import Foundation
import SwiftUI

@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var targetDirectoryURL: URL
    @Published private(set) var projectSizeBytes: Int64 = 0
    @Published private(set) var artifacts: [CleanArtifact] = []
    @Published var selectedArtifactIDs: Set<UUID> = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var isCleaning: Bool = false
    @Published private(set) var hasCompletedScan: Bool = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastRunOutput: String = ""
    @Published private(set) var lastScanDate: Date?
    @Published var hoveredPathPreview: String?
    @Published var showCleanConfirmation: Bool = false
    @Published var sizeSortDirection: SizeSortDirection = .descending

    private var hasPerformedInitialScan = false

    private enum CleanerError: LocalizedError {
        case invalidDirectory
        case scriptNotFound
        case processLaunch(String)
        case processFailed(Int32, String)
        case parseError
        case unsafePath(String)

        var errorDescription: String? {
            switch self {
            case .invalidDirectory:
                return "Selected directory is invalid."
            case .scriptNotFound:
                return "safe_clean.sh was not found in app resources."
            case let .processLaunch(message):
                return "Failed to run cleaner script: \(message)"
            case let .processFailed(code, output):
                return "Cleaner script exited with code \(code).\n\n\(output)"
            case .parseError:
                return "Failed to parse scan output."
            case let .unsafePath(path):
                return "Unsafe cleanup path blocked: \(path)"
            }
        }
    }

    init(initialDirectory: URL = URL(fileURLWithPath: "\(NSHomeDirectory())/Documents/Develop", isDirectory: true)) {
        targetDirectoryURL = initialDirectory
    }

    var directoryName: String {
        let name = targetDirectoryURL.lastPathComponent
        return name.isEmpty ? targetDirectoryURL.path : name
    }

    var directoryPath: String {
        targetDirectoryURL.path
    }

    var isBusy: Bool {
        isScanning || isCleaning
    }

    var removableBytes: Int64 {
        artifacts.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedBytes: Int64 {
        artifacts
            .filter { selectedArtifactIDs.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    var bytesAfterCleanup: Int64 {
        max(projectSizeBytes - selectedBytes, 0)
    }

    var cleanupProgress: Double {
        guard projectSizeBytes > 0 else { return 0 }
        return min(max(Double(selectedBytes) / Double(projectSizeBytes), 0), 1)
    }

    var scanReady: Bool {
        hasCompletedScan && lastErrorMessage == nil
    }

    var canClean: Bool {
        scanReady && selectedBytes > 0 && !isBusy
    }

    var allItemsSelected: Bool {
        !artifacts.isEmpty && selectedArtifactIDs.count == artifacts.count
    }

    var formattedProjectSize: String {
        formatBytes(projectSizeBytes)
    }

    var formattedRemovableSize: String {
        formatBytes(removableBytes)
    }

    var formattedSelectedSize: String {
        formatBytes(selectedBytes)
    }

    var formattedAfterCleanupSize: String {
        formatBytes(bytesAfterCleanup)
    }

    var primaryStatusLabel: String {
        if isScanning {
            return "Scanning…"
        }

        if isCleaning {
            return "Cleaning…"
        }

        if hasCompletedScan {
            return "Scan complete"
        }

        return "Ready to scan"
    }

    var secondaryStatusLabel: String {
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            return lastErrorMessage
        }

        if !hasCompletedScan {
            return "No scan yet"
        }

        return "Safe to clean"
    }

    var primaryStatusSymbol: String {
        if isScanning || isCleaning {
            return "clock"
        }

        return hasCompletedScan ? "checkmark.circle.fill" : "circle"
    }

    var secondaryStatusSymbol: String {
        if lastErrorMessage != nil {
            return "exclamationmark.triangle.fill"
        }

        return hasCompletedScan ? "checkmark.shield.fill" : "shield"
    }

    func formatBytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: value)
    }

    func chooseDirectory() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.directoryURL = targetDirectoryURL

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        targetDirectoryURL = selectedURL
        rescan()
    }

    func performInitialScanIfNeeded() {
        guard !hasPerformedInitialScan else { return }
        hasPerformedInitialScan = true
        rescan()
    }

    func rescan() {
        guard !isBusy else { return }

        Task {
            await scan()
        }
    }

    func requestClean() {
        guard canClean else { return }
        showCleanConfirmation = true
    }

    func confirmClean() {
        guard canClean else { return }
        showCleanConfirmation = false

        Task {
            await cleanSelectedArtifacts()
            if lastErrorMessage == nil {
                await scan()
            }
        }
    }

    func setSelection(_ selected: Bool, for artifactID: UUID) {
        if selected {
            selectedArtifactIDs.insert(artifactID)
        } else {
            selectedArtifactIDs.remove(artifactID)
        }
    }

    func setSelectAll(_ enabled: Bool) {
        if enabled {
            selectedArtifactIDs = Set(artifacts.map(\.id))
        } else {
            selectedArtifactIDs.removeAll()
        }
    }

    func toggleSizeSort() {
        sizeSortDirection.toggle()
        applySort()
    }

    func setHoveredPath(_ path: String?) {
        hoveredPathPreview = path
    }

    private func scan() async {
        guard !isBusy else { return }

        guard FileManager.default.fileExists(atPath: targetDirectoryURL.path) else {
            lastErrorMessage = CleanerError.invalidDirectory.localizedDescription
            return
        }

        guard let scriptURL = resolveScriptURL() else {
            lastErrorMessage = CleanerError.scriptNotFound.localizedDescription
            return
        }

        isScanning = true
        lastErrorMessage = nil

        do {
            let output = try await Self.executeScript(
                scriptURL: scriptURL,
                workingDirectory: targetDirectoryURL,
                arguments: [],
                stdinText: nil
            )

            let snapshot = try Self.parseDryRunOutput(output)

            withAnimation(.easeInOut(duration: 0.2)) {
                projectSizeBytes = snapshot.projectSizeBytes
                artifacts = snapshot.artifacts
                selectedArtifactIDs = Set(snapshot.artifacts.map(\.id))
                applySort()
                lastRunOutput = output
                lastScanDate = Date()
                hasCompletedScan = true
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            lastRunOutput = ""
        }

        isScanning = false
    }

    private func cleanSelectedArtifacts() async {
        guard !isBusy else { return }

        let selected = artifacts.filter { selectedArtifactIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        isCleaning = true
        lastErrorMessage = nil

        let root = targetDirectoryURL.standardizedFileURL

        do {
            try await Task.detached(priority: .userInitiated) {
                for artifact in selected {
                    let path = artifact.absoluteURL(root: root)
                    try Self.removeSafely(path, inside: root)
                }
            }.value
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isCleaning = false
    }

    private func applySort() {
        switch sizeSortDirection {
        case .descending:
            artifacts.sort { lhs, rhs in
                if lhs.sizeBytes == rhs.sizeBytes {
                    return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
                }
                return lhs.sizeBytes > rhs.sizeBytes
            }
        case .ascending:
            artifacts.sort { lhs, rhs in
                if lhs.sizeBytes == rhs.sizeBytes {
                    return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
                }
                return lhs.sizeBytes < rhs.sizeBytes
            }
        }
    }

    private func resolveScriptURL() -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("scripts/safe_clean.sh")
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let localScript = currentDirectory.appendingPathComponent("scripts/safe_clean.sh")
        if FileManager.default.isExecutableFile(atPath: localScript.path) {
            return localScript
        }

        return nil
    }

    nonisolated private static func removeSafely(_ url: URL, inside root: URL) throws {
        let resolvedRoot = root.standardizedFileURL.path
        let resolvedPath = url.standardizedFileURL.path

        guard resolvedPath.hasPrefix(resolvedRoot + "/") else {
            throw CleanerError.unsafePath(resolvedPath)
        }

        if resolvedPath == resolvedRoot || resolvedPath.contains("/.git/") || resolvedPath.hasSuffix("/.git") {
            throw CleanerError.unsafePath(resolvedPath)
        }

        if FileManager.default.fileExists(atPath: resolvedPath) {
            try FileManager.default.removeItem(atPath: resolvedPath)
        }
    }

    nonisolated private static func executeScript(
        scriptURL: URL,
        workingDirectory: URL,
        arguments: [String],
        stdinText: String?
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.currentDirectoryURL = workingDirectory
                process.arguments = [scriptURL.path] + arguments

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                let inputPipe: Pipe?
                if stdinText != nil {
                    let pipe = Pipe()
                    process.standardInput = pipe
                    inputPipe = pipe
                } else {
                    inputPipe = nil
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CleanerError.processLaunch(error.localizedDescription))
                    return
                }

                if let stdinText, let inputPipe,
                   let inputData = stdinText.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(inputData)
                    try? inputPipe.fileHandleForWriting.close()
                }

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: outputData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: CleanerError.processFailed(process.terminationStatus, output))
                }
            }
        }
    }

    nonisolated private static func parseDryRunOutput(_ output: String) throws -> (projectSizeBytes: Int64, artifacts: [CleanArtifact]) {
        let lines = output.components(separatedBy: .newlines)
        var projectSizeBytes: Int64?
        var artifacts: [CleanArtifact] = []
        var inArtifactsSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("Размер проекта:") {
                let sizeString = trimmed.replacingOccurrences(of: "Размер проекта:", with: "").trimmingCharacters(in: .whitespaces)
                projectSizeBytes = parseSize(sizeString)
                continue
            }

            if trimmed == "Найдено для удаления:" {
                inArtifactsSection = true
                continue
            }

            if trimmed.hasPrefix("Суммарный размер к удалению:") {
                inArtifactsSection = false
                continue
            }

            if !inArtifactsSection || trimmed.isEmpty || trimmed == "(ничего не найдено)" {
                continue
            }

            if let entry = parseArtifactLine(line) {
                let artifact = CleanArtifact(
                    relativePath: entry.path,
                    sizeBytes: entry.bytes,
                    kind: classify(path: entry.path)
                )
                artifacts.append(artifact)
            }
        }

        guard let projectSizeBytes else {
            throw CleanerError.parseError
        }

        return (projectSizeBytes, artifacts)
    }

    nonisolated private static func parseArtifactLine(_ line: String) -> (bytes: Int64, path: String)? {
        let pattern = #"^\s*([0-9]+(?:\.[0-9]+)?)\s+(B|KiB|MiB|GiB|TiB)\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range), match.numberOfRanges == 4,
              let valueRange = Range(match.range(at: 1), in: line),
              let unitRange = Range(match.range(at: 2), in: line),
              let pathRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let valueString = String(line[valueRange])
        let unitString = String(line[unitRange])
        let pathString = String(line[pathRange])

        guard let bytes = parseSize("\(valueString) \(unitString)") else {
            return nil
        }

        return (bytes, pathString)
    }

    nonisolated private static func parseSize(_ value: String) -> Int64? {
        let pattern = #"^\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(location: 0, length: value.utf16.count)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              let amountRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let amount = Double(value[amountRange]) else {
            return nil
        }

        let unit = String(value[unitRange])

        let multiplier: Double
        switch unit {
        case "B":
            multiplier = 1
        case "KiB":
            multiplier = 1024
        case "MiB":
            multiplier = 1024 * 1024
        case "GiB":
            multiplier = 1024 * 1024 * 1024
        case "TiB":
            multiplier = 1024 * 1024 * 1024 * 1024
        default:
            return nil
        }

        return Int64((amount * multiplier).rounded())
    }

    nonisolated private static func classify(path: String) -> ArtifactKind {
        let lower = path.lowercased()

        if lower.contains("node_modules") {
            return .node
        }

        if lower.contains(".build") || lower.contains("deriveddata") || lower.contains("xcuserdata") || lower.hasSuffix(".xcuserstate") {
            return .swift
        }

        if lower.contains("__pycache__") || lower.contains(".pytest_cache") || lower.contains(".mypy_cache") || lower.hasSuffix(".pyc") {
            return .python
        }

        if lower.hasSuffix("/target") || lower.contains("/target/") {
            return .rust
        }

        if lower.hasSuffix("/bin") || lower.contains("/bin/") || lower.hasSuffix("/pkg") || lower.contains("/pkg/") {
            return .go
        }

        if lower.contains("cmake") {
            return .cpp
        }

        if lower.contains(".codex") || lower.contains(".agent") {
            return .codex
        }

        if lower.hasSuffix(".log") || lower.hasSuffix(".ds_store") || lower.hasSuffix(".pyc") || lower.hasSuffix("cmakecache.txt") {
            return .file
        }

        return .folder
    }
}
