import Foundation

enum ArtifactKind: String, CaseIterable, Hashable, Sendable {
    case node
    case swift
    case python
    case rust
    case go
    case cpp
    case codex
    case file
    case folder

    var symbolName: String {
        switch self {
        case .node:
            return "shippingbox"
        case .swift:
            return "hammer"
        case .python:
            return "chevron.left.forwardslash.chevron.right"
        case .rust:
            return "gearshape.2"
        case .go:
            return "arrow.triangle.branch"
        case .cpp:
            return "wrench.and.screwdriver"
        case .codex:
            return "sparkles.rectangle.stack"
        case .file:
            return "doc"
        case .folder:
            return "folder"
        }
    }

    var displayName: String {
        switch self {
        case .node:
            return "Node"
        case .swift:
            return "Swift"
        case .python:
            return "Python"
        case .rust:
            return "Rust"
        case .go:
            return "Go"
        case .cpp:
            return "C/C++"
        case .codex:
            return "Codex"
        case .file:
            return "File"
        case .folder:
            return "Folder"
        }
    }
}

struct CleanArtifact: Identifiable, Hashable, Sendable {
    let id: UUID
    let relativePath: String
    let sizeBytes: Int64
    let kind: ArtifactKind

    init(relativePath: String, sizeBytes: Int64, kind: ArtifactKind) {
        self.id = UUID()
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.kind = kind
    }

    var name: String {
        let candidate = URL(fileURLWithPath: relativePath).lastPathComponent
        return candidate.isEmpty ? relativePath : candidate
    }

    func absoluteURL(root: URL) -> URL {
        root.appendingPathComponent(relativePath)
    }
}

enum SizeSortDirection: Sendable {
    case descending
    case ascending

    mutating func toggle() {
        self = self == .descending ? .ascending : .descending
    }
}
