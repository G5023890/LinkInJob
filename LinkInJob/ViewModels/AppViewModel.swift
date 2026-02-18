import AppKit
import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    private static let sortDefaultsKey = "app.sortOption"
    private static let sidebarDefaultsKey = "app.sidebarFilter"
    private lazy var projectRootDirectory: String = Self.resolveProjectRootDirectory()

    enum SidebarFilter: Hashable {
        case stage(Stage)
        case starred
        case noReply

        var title: String {
            switch self {
            case .stage(let stage):
                return stage.title
            case .starred:
                return "Starred"
            case .noReply:
                return "No reply > 5 days"
            }
        }

        var symbol: String {
            switch self {
            case .stage(let stage):
                return stage.symbol
            case .starred:
                return "star"
            case .noReply:
                return "clock.badge.exclamationmark"
            }
        }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case date = "Date"
        case age = "Age"
        case company = "Company"

        var id: String { rawValue }
    }

    @Published var applications: [ApplicationItem]
    @Published var selectedStage: Stage = .inbox
    @Published var selectedItemID: ApplicationItem.ID?
    @Published var searchText: String = ""
    @Published var sidebarFilter: SidebarFilter = .stage(.inbox) {
        didSet {
            UserDefaults.standard.set(encodeSidebarFilter(sidebarFilter), forKey: Self.sidebarDefaultsKey)
        }
    }
    @Published var sortOption: SortOption = .date {
        didSet {
            UserDefaults.standard.set(sortOption.rawValue, forKey: Self.sortDefaultsKey)
        }
    }
    @Published var dataSourceLabel: String = "Mock data"
    @Published var isSyncing: Bool = false
    @Published var syncStatusText: String = ""

    init(applications: [ApplicationItem] = AppViewModel.mockApplications()) {
        self.applications = applications
        if let rawSort = UserDefaults.standard.string(forKey: Self.sortDefaultsKey),
           let savedSort = SortOption(rawValue: rawSort) {
            self.sortOption = savedSort
        }
        if let rawFilter = UserDefaults.standard.string(forKey: Self.sidebarDefaultsKey),
           let savedFilter = decodeSidebarFilter(rawFilter) {
            self.sidebarFilter = savedFilter
            if case .stage(let stage) = savedFilter {
                self.selectedStage = stage
            }
        }
        self.selectedItemID = applications.first?.id
    }

    func loadFromBridge() async {
        await ensureStarredColumn()
        let loaded = (try? await PythonBridge().fetchApplications()) ?? []
        guard !loaded.isEmpty else { return }
        applications = loaded
        dataSourceLabel = "SQLite"
        ensureSelectionIsVisible()
    }

    func runProcessingPipeline() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncStatusText = "Syncing..."
        defer { isSyncing = false }

        let sourceDirs = availableSourceDirectories()
        guard !sourceDirs.isEmpty else {
            syncStatusText = "No source folder"
            return
        }

        let projectDir = projectRootDirectory
        let parserRunner = "\(projectDir)/parser/runner.py"
        let driveSyncScript = "\(projectDir)/scripts/sync_drive_rclone.sh"
        let scriptsDirEscaped = "\(projectDir)/scripts"
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let driveSyncExit = await runCommand(
            launchPath: "/bin/bash",
            arguments: [driveSyncScript],
            currentDirectory: projectDir
        )

        var parserOk = true
        for sourceDir in sourceDirs {
            let parserExit = await runCommand(
                launchPath: "/usr/bin/python3",
                arguments: [parserRunner, sourceDir],
                currentDirectory: projectDir
            )
            if parserExit != 0 {
                parserOk = false
            }
        }

        let sourceDirLiteral = sourceDirs
            .map { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") }
            .map { "Path('\($0)')" }
            .joined(separator: ", ")

let syncScript = """
import sys
from pathlib import Path
sys.path.insert(0, '\(scriptsDirEscaped)')
from linkedin_applications_gui_sql import ApplicationsDB
source_dirs = [\(sourceDirLiteral)]
db_path = str(Path.home() / '.local' / 'share' / 'linkedin_apps' / 'applications.db')
db = ApplicationsDB(db_path)
try:
    before = db.conn.execute("SELECT COUNT(*) FROM applications").fetchone()[0]
    db.snapshot_non_incoming_statuses()
    for source_dir in source_dirs:
        if source_dir.exists():
            db.sync_source_dir(source_dir)
    db.translate_existing_about_job_texts()
    db.conn.commit()
    after = db.conn.execute("SELECT COUNT(*) FROM applications").fetchone()[0]
    print(after - before)
finally:
    db.close()
"""

        let syncExit = await runCommand(
            launchPath: "/usr/bin/python3",
            arguments: ["-c", syncScript],
            currentDirectory: projectDir
        )

        await loadFromBridge()
        syncStatusText = (driveSyncExit == 0 && parserOk && syncExit == 0) ? "Synced (\(sourceDirs.count) src)" : "Sync failed"
    }

    var selectedItem: ApplicationItem? {
        get {
            guard let id = selectedItemID else { return nil }
            return applications.first(where: { $0.id == id })
        }
        set {
            selectedItemID = newValue?.id
        }
    }

    var filteredApplications: [ApplicationItem] {
        var items = applications.filter { matchesSidebarFilter($0) }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchText.lowercased()
            items = items.filter {
                $0.company.lowercased().contains(query)
                    || $0.role.lowercased().contains(query)
                    || $0.location.lowercased().contains(query)
            }
        }

        switch sortOption {
        case .date:
            items.sort { lhs, rhs in
                (lhs.lastActivityDate ?? lhs.appliedDate ?? .distantPast) > (rhs.lastActivityDate ?? rhs.appliedDate ?? .distantPast)
            }
        case .age:
            items.sort { $0.daysSinceLastActivity > $1.daysSinceLastActivity }
        case .company:
            items.sort { $0.company.localizedCaseInsensitiveCompare($1.company) == .orderedAscending }
        }

        return items
    }

    var stageCounts: [Stage: Int] {
        Dictionary(uniqueKeysWithValues: Stage.allCases.map { stage in
            (stage, applications.filter { $0.effectiveStage == stage }.count)
        })
    }

    var starredCount: Int {
        applications.filter(\.starred).count
    }

    var noReplyCount: Int {
        applications.filter(\.needsFollowUp).count
    }

    func select(stage: Stage) {
        selectedStage = stage
        sidebarFilter = .stage(stage)
        ensureSelectionIsVisible()
    }

    func selectFilter(_ filter: SidebarFilter) {
        sidebarFilter = filter
        if case .stage(let stage) = filter {
            selectedStage = stage
        }
        ensureSelectionIsVisible()
    }

    func setStage(_ stage: Stage, for item: ApplicationItem) {
        update(itemID: item.id) { $0.manualStage = stage }
        persistManualStage(for: item.id, manualStage: stage)
    }

    func resetToAuto(for item: ApplicationItem) {
        update(itemID: item.id) { $0.manualStage = nil }
        persistManualStage(for: item.id, manualStage: nil)
    }

    func toggleStar(for item: ApplicationItem) {
        update(itemID: item.id) { $0.starred.toggle() }
        guard let updated = applications.first(where: { $0.id == item.id }) else { return }
        persistStar(for: updated.id, starred: updated.starred)
    }

    func openJobLink(for item: ApplicationItem) {
        let candidates = jobURLCandidates(from: item.jobURL)
        guard !candidates.isEmpty else {
            openSourceFile(for: item)
            return
        }
        let opened = candidates.contains { NSWorkspace.shared.open($0) }
        if !opened {
            openSourceFile(for: item)
        }
    }

    func openSourceFile(for item: ApplicationItem) {
        let path = (item.sourceFilePath as NSString).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.open(fileURL)
            return
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
    }

    func copyFollowUp(for item: ApplicationItem) {
        guard item.needsFollowUp else { return }
        let template = """
        Hi \(item.company) team,

        I wanted to follow up on my application for the \(item.role) role.
        I remain very interested and would love to hear about next steps.

        Thank you,
        """
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(template, forType: .string)
    }

    func handleListHotkey(_ key: String) {
        guard let item = selectedItem else { return }
        switch key.lowercased() {
        case "i":
            setStage(.interview, for: item)
        case "r":
            setStage(.rejected, for: item)
        case "a":
            setStage(.archive, for: item)
        case "s":
            toggleStar(for: item)
        case "f":
            copyFollowUp(for: item)
        default:
            break
        }
    }

    func timeline(for item: ApplicationItem) -> [ActivityEvent] {
        var events: [ActivityEvent] = []

        if let appliedDate = item.appliedDate {
            events.append(ActivityEvent(date: appliedDate, type: "applied", text: "Applied to \(item.company) for \(item.role)"))
        }

        if let lastActivityDate = item.lastActivityDate, lastActivityDate != item.appliedDate {
            let text: String
            switch item.effectiveStage {
            case .interview:
                text = "Interview update received"
            case .offer:
                text = "Offer-related activity"
            case .rejected:
                text = "Rejection received"
            default:
                text = "Auto reply or status update"
            }
            events.append(ActivityEvent(date: lastActivityDate, type: "activity", text: text))
        }

        if let manualStage = item.manualStage {
            events.append(ActivityEvent(date: Date(), type: "manual", text: "Manual stage set to \(manualStage.title)"))
        }

        return events.sorted { $0.date > $1.date }
    }

    private func matchesSidebarFilter(_ item: ApplicationItem) -> Bool {
        switch sidebarFilter {
        case .stage(let stage):
            return item.effectiveStage == stage
        case .starred:
            return item.starred
        case .noReply:
            return item.needsFollowUp
        }
    }

    private func ensureSelectionIsVisible() {
        if let selected = selectedItem, filteredApplications.contains(where: { $0.id == selected.id }) {
            return
        }
        selectedItemID = filteredApplications.first?.id
    }

    private func update(itemID: UUID, _ mutate: (inout ApplicationItem) -> Void) {
        guard let index = applications.firstIndex(where: { $0.id == itemID }) else { return }
        mutate(&applications[index])
        objectWillChange.send()
    }

    private func persistManualStage(for itemID: UUID, manualStage: Stage?) {
        guard let item = applications.first(where: { $0.id == itemID }) else { return }
        let manual = dbStatus(for: manualStage)
        let manualLiteral = manual.map { "'\($0)'" } ?? "None"
        let source = item.sourceFilePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let link = (item.jobURL ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let dbIDLiteral = item.dbID.map(String.init) ?? "None"

        let script = """
import sqlite3
from pathlib import Path
db_path = str(Path.home() / '.local' / 'share' / 'linkedin_apps' / 'applications.db')
conn = sqlite3.connect(db_path)
cur = conn.cursor()
db_id = \(dbIDLiteral)
source = '\(source)'
link = '\(link)'
if db_id is not None:
    cur.execute(\"\"\"SELECT id, record_key, auto_status FROM applications
WHERE id = ?\"\"\", (db_id,))
else:
    cur.execute(\"\"\"SELECT id, record_key, auto_status FROM applications
WHERE source_file = ? AND COALESCE(link_url, '') = ?
ORDER BY id DESC LIMIT 1\"\"\", (source, link))
row = cur.fetchone()
if row:
    app_id, record_key, auto_status = row
    manual_status = \(manualLiteral)
    current_status = manual_status if manual_status else (auto_status or 'incoming')
    cur.execute(\"\"\"UPDATE applications
SET manual_status = ?, current_status = ?, updated_at = CURRENT_TIMESTAMP
WHERE id = ?\"\"\", (manual_status, current_status, app_id))
    if current_status and current_status != 'incoming':
        cur.execute(\"\"\"INSERT INTO status_pins(record_key, pinned_status, updated_at)
VALUES (?, ?, CURRENT_TIMESTAMP)
ON CONFLICT(record_key) DO UPDATE SET pinned_status = excluded.pinned_status, updated_at = CURRENT_TIMESTAMP\"\"\", (record_key, current_status))
    else:
        cur.execute(\"DELETE FROM status_pins WHERE record_key = ?\", (record_key,))
conn.commit()
conn.close()
"""

        Task {
            let exit = await runCommand(
                launchPath: "/usr/bin/python3",
                arguments: ["-c", script],
                currentDirectory: projectRootDirectory
            )
            if exit != 0 {
                syncStatusText = "Save failed"
            }
        }
    }

    private func persistStar(for itemID: UUID, starred: Bool) {
        guard let item = applications.first(where: { $0.id == itemID }) else { return }
        let source = item.sourceFilePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let link = (item.jobURL ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let dbIDLiteral = item.dbID.map(String.init) ?? "None"
        let starredValue = starred ? 1 : 0

        let script = """
import sqlite3
from pathlib import Path
db_path = str(Path.home() / '.local' / 'share' / 'linkedin_apps' / 'applications.db')
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cols = [r[1] for r in cur.execute("PRAGMA table_info(applications)").fetchall()]
if "starred" not in cols:
    cur.execute("ALTER TABLE applications ADD COLUMN starred INTEGER NOT NULL DEFAULT 0")
db_id = \(dbIDLiteral)
source = '\(source)'
link = '\(link)'
if db_id is not None:
    cur.execute("UPDATE applications SET starred = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", (\(starredValue), db_id))
else:
    cur.execute(\"\"\"UPDATE applications
SET starred = ?, updated_at = CURRENT_TIMESTAMP
WHERE id = (
    SELECT id FROM applications
    WHERE source_file = ? AND COALESCE(link_url, '') = ?
    ORDER BY id DESC LIMIT 1
)\"\"\", (\(starredValue), source, link))
conn.commit()
conn.close()
"""

        Task {
            let exit = await runCommand(
                launchPath: "/usr/bin/python3",
                arguments: ["-c", script],
                currentDirectory: projectRootDirectory
            )
            if exit != 0 {
                syncStatusText = "Star save failed"
            }
        }
    }

    private func dbStatus(for stage: Stage?) -> String? {
        guard let stage else { return nil }
        switch stage {
        case .inbox:
            return "incoming"
        case .applied:
            return "applied"
        case .interview:
            return "interview"
        case .offer:
            return "offer"
        case .rejected:
            return "rejected"
        case .archive:
            return "archive"
        }
    }

    private func encodeSidebarFilter(_ filter: SidebarFilter) -> String {
        switch filter {
        case .stage(let stage):
            return "stage:\(stage.rawValue)"
        case .starred:
            return "starred"
        case .noReply:
            return "noReply"
        }
    }

    private func decodeSidebarFilter(_ raw: String) -> SidebarFilter? {
        if raw == "starred" { return .starred }
        if raw == "noReply" { return .noReply }
        if raw.hasPrefix("stage:") {
            let value = String(raw.dropFirst("stage:".count))
            if let stage = Stage(rawValue: value) {
                return .stage(stage)
            }
        }
        return nil
    }

    private func runCommand(launchPath: String, arguments: [String], currentDirectory: String) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: 1)
                }
            }
        }
    }

    private func ensureStarredColumn() async {
        let script = """
import sqlite3
from pathlib import Path
db_path = str(Path.home() / '.local' / 'share' / 'linkedin_apps' / 'applications.db')
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cols = [r[1] for r in cur.execute("PRAGMA table_info(applications)").fetchall()]
if "starred" not in cols:
    cur.execute("ALTER TABLE applications ADD COLUMN starred INTEGER NOT NULL DEFAULT 0")
conn.commit()
conn.close()
"""
        _ = await runCommand(
            launchPath: "/usr/bin/python3",
            arguments: ["-c", script],
            currentDirectory: projectRootDirectory
        )
    }

    private func availableSourceDirectories() -> [String] {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/Library/Application Support/DriveCVSync/LinkedIn email",
            "\(home)/Library/Application Support/DriveCVSync/LinkedIn Archive"
        ]
        let fm = FileManager.default
        return candidates.filter {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue
        }
    }

    private static func resolveProjectRootDirectory() -> String {
        let fm = FileManager.default

        func looksLikeProjectRoot(_ path: String) -> Bool {
            let scripts = (path as NSString).appendingPathComponent("scripts")
            let parser = (path as NSString).appendingPathComponent("parser")
            let app = (path as NSString).appendingPathComponent("LinkInJob")
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: scripts, isDirectory: &isDir) && isDir.boolValue
                && fm.fileExists(atPath: parser, isDirectory: &isDir) && isDir.boolValue
                && fm.fileExists(atPath: app, isDirectory: &isDir) && isDir.boolValue
        }

        if let env = ProcessInfo.processInfo.environment["LINKEDIN_PROJECT_DIR"], !env.isEmpty, looksLikeProjectRoot(env) {
            return env
        }

        let cwd = fm.currentDirectoryPath
        if looksLikeProjectRoot(cwd) {
            return cwd
        }

        let homeCandidate = (NSHomeDirectory() as NSString).appendingPathComponent("Documents/Develop/LinkedIn")
        if looksLikeProjectRoot(homeCandidate) {
            return homeCandidate
        }

        return cwd
    }

    private func jobURLCandidates(from raw: String?) -> [URL] {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return []
        }

        if !value.lowercased().hasPrefix("http://"), !value.lowercased().hasPrefix("https://") {
            value = "https://\(value)"
        }

        var urls: [String] = []

        if let extracted = extractLinkedInJobId(from: value) {
            if value.localizedCaseInsensitiveContains("/comm/jobs/view/") {
                urls.append("https://www.linkedin.com/comm/jobs/view/\(extracted)/")
            } else {
                urls.append("https://www.linkedin.com/jobs/view/\(extracted)/")
            }
        }

        if let comps = URLComponents(string: value), let host = comps.host?.lowercased(), host.contains("linkedin.com") {
            let path = comps.path
            if let match = path.range(of: #"/(comm/)?company/([^/]+)/jobs/?$"#, options: .regularExpression) {
                let normalized = String(path[match])
                if let slugMatch = normalized.range(of: #"/(comm/)?company/([^/]+)/jobs/?$"#, options: .regularExpression) {
                    let candidate = String(normalized[slugMatch])
                    let slugParts = candidate.split(separator: "/")
                    if slugParts.count >= 3 {
                        let slug = String(slugParts[2])
                        urls.append("https://www.linkedin.com/comm/company/\(slug)/jobs/")
                        urls.append("https://www.linkedin.com/company/\(slug)/jobs/")
                    }
                }
            } else if let match = path.range(of: #"/(comm/)?company/([^/]+)/?$"#, options: .regularExpression) {
                let candidate = String(path[match])
                let slugParts = candidate.split(separator: "/")
                if slugParts.count >= 2 {
                    let slug = String(slugParts[1] == "comm" ? slugParts[2] : slugParts[1])
                    urls.append("https://www.linkedin.com/comm/company/\(slug)/jobs/")
                    urls.append("https://www.linkedin.com/company/\(slug)/jobs/")
                }
            }
        }

        if var components = URLComponents(string: value) {
            components.query = nil
            components.fragment = nil
            if let cleaned = components.url?.absoluteString {
                urls.append(cleaned)
            }
        }

        urls.append(value)

        var result: [URL] = []
        var seen = Set<String>()
        for rawURL in urls {
            if seen.contains(rawURL) { continue }
            guard let url = URL(string: rawURL), url.scheme?.hasPrefix("http") == true else { continue }
            seen.insert(rawURL)
            result.append(url)
        }
        return result
    }

    private func extractLinkedInJobId(from value: String) -> String? {
        let pattern = #"linkedin\.com/(?:comm/)?jobs/view/(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(value.startIndex..., in: value)
        guard
            let match = regex.firstMatch(in: value, options: [], range: range),
            match.numberOfRanges > 1,
            let idRange = Range(match.range(at: 1), in: value)
        else {
            return nil
        }
        return String(value[idRange])
    }

    private static func mockApplications() -> [ApplicationItem] {
        let companies = [
            "Apple", "Notion", "Stripe", "Figma", "Airbnb", "Shopify", "Linear", "Atlassian", "Dropbox", "Miro",
            "Canva", "GitHub", "Datadog", "Snowflake", "Nvidia", "Cloudflare", "Slack", "Asana", "Mercury", "Plaid",
            "OpenAI", "Scale", "Brex", "Deel", "Rippling", "Vercel", "Twilio", "Okta", "HubSpot", "Zapier"
        ]

        let roles = [
            "System Administrator", "IT Support Engineer", "Site Reliability Engineer", "Platform Engineer", "DevOps Engineer",
            "Infrastructure Engineer", "Security Engineer"
        ]

        let locations = ["Remote", "New York, NY", "San Francisco, CA", "Austin, TX", "Seattle, WA", "Chicago, IL"]
        let descriptions = [
            "Build and maintain reliable internal infrastructure. Partner with security and product teams.",
            "Own macOS fleet management, identity integrations, and endpoint compliance.",
            "Scale platform tooling and improve incident response workflows.",
            nil
        ]

        return (0..<30).map { index in
            let autoStage = Stage.allCases[index % Stage.allCases.count]
            let daysAgo = Int.random(in: 1...14)
            let applied = Calendar.current.date(byAdding: .day, value: -(daysAgo + Int.random(in: 1...6)), to: Date())
            let activity = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())

            return ApplicationItem(
                id: UUID(),
                dbID: nil,
                company: companies[index % companies.count],
                role: roles[index % roles.count],
                location: locations[index % locations.count],
                subject: "Your application update",
                appliedDate: applied,
                lastActivityDate: activity,
                autoStage: autoStage,
                manualStage: index % 7 == 0 ? .interview : nil,
                sourceFilePath: "\(NSHomeDirectory())/Desktop/CV/LinkedIn email/email_\(index).txt",
                jobURL: index % 3 == 0 ? "https://www.linkedin.com/jobs/view/\(100_000 + index)" : nil,
                descriptionText: descriptions[index % descriptions.count],
                starred: index % 4 == 0
            )
        }
    }
}
