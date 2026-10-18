import Foundation

/// Local learning-to-rank for the launcher.
///
/// The order is built in layers:
///   1. match tier: exact > prefix > word > substring > fuzzy
///   2. learned usage: frequency, recency, "just opened", query affinity, time of day
///   3. query intent: file-like queries favour files, URL-like queries favour sites
///
/// Everything stays on disk in `ranking.json`. Commands are deliberately never
/// boosted by usage: a frequently used SLEEP or CSL SETTINGS must not sneak to
/// the top. The learning is small, bounded and has no network component.
final class ResultRanker {
    static let shared = ResultRanker()

    private struct Usage: Codable {
        var count: Int = 0
        var revealCount: Int = 0
        var lastUsed: Date = .distantPast
        var tokens: [String: Int] = [:]
        var hourBuckets: [Int] = Array(repeating: 0, count: 6)
        var weekdayCount: Int = 0
        var weekendCount: Int = 0
    }

    private struct FolderUse: Codable {
        var path: String
        var lastUsed: Date
    }

    private struct RankingData: Codable {
        var version: Int = 1
        var items: [String: Usage] = [:]
        var recent: [String] = []
        var recentFolders: [FolderUse]? = nil
    }

    private struct PendingRecord {
        let id: String
        let title: String
        let kind: ResultKind
        let query: String
        let revealed: Bool
        let date: Date
        let url: URL?
    }

    private struct Intent {
        var files = 0
        var websites = 0

        func boost(for kind: ResultKind) -> Int {
            switch kind {
            case .file: return files
            case .website: return websites
            case .application, .command: return 0
            }
        }
    }

    private var data = RankingData()
    private var pending: [PendingRecord] = []
    private var isLoaded = false
    private var didStartLoading = false
    private var resetBeforeLoad = false
    private var dirty = false
    private var loadCompletions: [() -> Void] = []
    private var saveWork: DispatchWorkItem?
    private let ioQueue = DispatchQueue(label: "com.henri.csl.ranking-io", qos: .utility)

    private let maxItems = 2500
    private let maxRecent = 40
    private let maxTokens = 8
    private let personalCap = 150.0

    private init() {}

    // MARK: - Lifecycle

    func loadAsync(completion: (() -> Void)? = nil) {
        if isLoaded {
            completion?()
            return
        }
        if let completion { loadCompletions.append(completion) }
        guard !didStartLoading else { return }
        didStartLoading = true

        ioQueue.async {
            let loaded = Self.read()
            DispatchQueue.main.async {
                if !self.resetBeforeLoad {
                    self.data = loaded
                    self.normalize()
                } else {
                    self.data = RankingData()
                }
                self.resetBeforeLoad = false
                self.isLoaded = true
                for record in self.pending {
                    self.apply(record)
                }
                self.pending.removeAll()
                self.trim()
                if self.dirty {
                    self.scheduleSave()
                }
                Log.debug("ranking loaded: \(self.data.items.count) items")
                let completions = self.loadCompletions
                self.loadCompletions.removeAll()
                completions.forEach { $0() }
            }
        }
    }

    /// Record a successful open/reveal. Commands are excluded on purpose.
    func record(_ result: SearchResult, query: String, revealed: Bool) {
        switch result.kind {
        case .command:
            return
        default:
            break
        }

        let record = PendingRecord(
            id: result.id,
            title: result.title,
            kind: result.kind,
            query: query,
            revealed: revealed,
            date: Date(),
            url: Self.fileURL(for: result)
        )
        if isLoaded {
            apply(record)
        } else {
            pending.append(record)
        }
    }

    func ranked(_ results: [SearchResult], query: String) -> [SearchResult] {
        guard !results.isEmpty else { return [] }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Self.baseSort(Self.dedupe(results))
        }

        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let hourBucket = min(5, max(0, hour / 4))
        let weekday = calendar.component(.weekday, from: now)
        let isWeekend = weekday == 1 || weekday == 7
        let tokens = Self.tokens(trimmed)
        let intent = Self.intent(for: trimmed, results: results)

        var recentPositions: [String: Int] = [:]
        for (index, id) in data.recent.enumerated() where recentPositions[id] == nil {
            recentPositions[id] = index
        }

        // Exact matches lose value when the same title exists many times
        // (six folders called "Settings" are rarely six good answers).
        var titleCounts: [String: Int] = [:]
        for result in results {
            titleCounts[result.title.lowercased(), default: 0] += 1
        }

        var seen = Set<String>()
        var scored: [(result: SearchResult, score: Int, tier: Int)] = []
        scored.reserveCapacity(results.count)

        for result in results {
            guard seen.insert(result.id).inserted else { continue }
            let rawTier = Self.tier(for: result, query: trimmed)
            var tier = rawTier

            var boost = intent.boost(for: result.kind)
            // A whole word inside an app name is a strong launcher signal
            // ("code" -> Visual Studio Code), even when the title is long.
            // Treat it like a prefix so noisy files such as CodeResources do
            // not outrank the app just because they start with the query.
            if result.kind == .application, rawTier == 2 {
                boost += 100
                tier = 1
            }
            if rawTier == 0, let count = titleCounts[result.title.lowercased()], count > 1 {
                // Ambiguous exact title: six "Settings" folders are not six
                // equally good answers. Demote them to prefix level and let a
                // unique command/app/file take over.
                tier = 1
                boost -= Int((40.0 * log2(Double(count))).rounded())
            }
            var personal = 0.0
            if let usage = data.items[result.id] {
                let uses = Double(usage.count) + 0.5 * Double(usage.revealCount)
                let frequency = min(70.0, 24.0 * log2(1.0 + uses))
                let days = max(0.0, now.timeIntervalSince(usage.lastUsed) / 86_400.0)
                let recency = 40.0 * exp(-days / 7.0)

                var recentBoost = 0.0
                if let position = recentPositions[result.id] {
                    recentBoost = position < 3 ? 18.0 : position < 10 ? 9.0 : position < 20 ? 4.0 : 0.0
                }

                let time = Self.timeBoost(
                    usage,
                    hourBucket: hourBucket,
                    isWeekend: isWeekend
                )
                let affinity = Self.affinity(usage, queryTokens: tokens)
                personal = frequency + recency + recentBoost + time + affinity
            }
            personal += folderBoost(for: result, now: now)

            let quality = Self.quality(forTier: tier)
            boost += Int((min(personalCap, personal) * quality).rounded())
            scored.append((result, result.score + boost, tier))
        }

        scored.sort {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.score != $1.score { return $0.score > $1.score }
            let leftKind = Self.kindRank($0.result.kind)
            let rightKind = Self.kindRank($1.result.kind)
            if leftKind != rightKind { return leftKind < rightKind }
            if $0.result.title.count != $1.result.title.count {
                return $0.result.title.count < $1.result.title.count
            }
            return $0.result.title.localizedCaseInsensitiveCompare($1.result.title) == .orderedAscending
        }

        return scored.map { $0.result.withScore($0.score) }
    }

    /// Mainly for `--rank-test`; a user can also delete ranking.json.
    func reset() {
        saveWork?.cancel()
        saveWork = nil
        resetBeforeLoad = !isLoaded
        data = RankingData()
        pending.removeAll()
        dirty = true
        saveNow()
        Log.debug("ranking reset")
    }

    func flush() {
        saveWork?.cancel()
        saveWork = nil
        guard didStartLoading else { return }
        let snapshot = data
        ioQueue.sync {
            Self.write(snapshot)
        }
        dirty = false
    }

    // MARK: - Learning

    private func apply(_ record: PendingRecord) {
        switch record.kind {
        case .command:
            return
        default:
            break
        }

        var usage = data.items[record.id] ?? Usage()
        usage.count += 1
        if record.revealed { usage.revealCount += 1 }
        usage.lastUsed = max(usage.lastUsed, record.date)

        var tokens = Set(Self.tokens(record.query))
        tokens.formUnion(Self.tokens(record.title))
        for token in tokens {
            usage.tokens[token, default: 0] += 1
        }
        if usage.tokens.count > maxTokens {
            let kept = usage.tokens
                .sorted {
                    if $0.value != $1.value { return $0.value > $1.value }
                    return $0.key < $1.key
                }
                .prefix(maxTokens)
            usage.tokens = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: record.date)
        let bucket = min(5, max(0, hour / 4))
        if usage.hourBuckets.count != 6 {
            usage.hourBuckets = Array(repeating: 0, count: 6)
        }
        usage.hourBuckets[bucket] += 1

        let weekday = calendar.component(.weekday, from: record.date)
        if weekday == 1 || weekday == 7 {
            usage.weekendCount += 1
        } else {
            usage.weekdayCount += 1
        }

        data.items[record.id] = usage
        data.recent.removeAll { $0 == record.id }
        data.recent.insert(record.id, at: 0)
        if data.recent.count > maxRecent {
            data.recent.removeLast(data.recent.count - maxRecent)
        }

        if case .file = record.kind, let url = record.url {
            Self.noteFolder(for: url, date: record.date, data: &data)
        }

        dirty = true
        trim()
        scheduleSave()
    }

    private func trim() {
        var folders = data.recentFolders ?? []
        if folders.count > 8 {
            folders.removeLast(folders.count - 8)
            data.recentFolders = folders
        }
        guard data.items.count > maxItems else { return }
        let recent = Set(data.recent)
        let sorted = data.items.keys.sorted { left, right in
            let leftRecent = recent.contains(left)
            let rightRecent = recent.contains(right)
            if leftRecent != rightRecent { return leftRecent }
            return (data.items[left]?.lastUsed ?? .distantPast) > (data.items[right]?.lastUsed ?? .distantPast)
        }
        let keep = Set(sorted.prefix(maxItems))
        data.items = data.items.filter { keep.contains($0.key) }
        data.recent = data.recent.filter { data.items[$0] != nil }
    }

    private func normalize() {
        data.items = data.items.mapValues { usage in
            var fixed = usage
            if fixed.hourBuckets.count != 6 {
                fixed.hourBuckets = Array(repeating: 0, count: 6)
            }
            fixed.count = max(0, fixed.count)
            fixed.revealCount = max(0, fixed.revealCount)
            return fixed
        }
        data.recent = data.recent.filter { data.items[$0] != nil }
        let folders = data.recentFolders ?? []
        if folders.count > 8 {
            data.recentFolders = Array(folders.prefix(8))
        }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveWork = nil
            self?.saveNow()
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func saveNow() {
        guard dirty else { return }
        dirty = false
        let snapshot = data
        ioQueue.async {
            Self.write(snapshot)
        }
    }

    private static func read() -> RankingData {
        guard let bytes = try? Data(contentsOf: AppPaths.rankingFile) else {
            return RankingData()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(RankingData.self, from: bytes)
        } catch {
            Log.debug("ranking decode failed: \(error)")
            return RankingData()
        }
    }

    private static func write(_ data: RankingData) {
        AppPaths.prepare()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            let bytes = try encoder.encode(data)
            try bytes.write(to: AppPaths.rankingFile, options: .atomic)
            Log.debug("ranking saved: \(data.items.count) items (\(bytes.count / 1024) KB)")
        } catch {
            Log.debug("ranking save failed: \(error)")
        }
    }

    // MARK: - Ranking ingredients

    private static func tier(for result: SearchResult, query: String) -> Int {
        let needle = query.lowercased()
        let title = result.title.lowercased()

        switch result.kind {
        case .command, .website:
            // Commands can match via keywords and websites via their host, so
            // their provider score is the reliable tier signal here.
            return baseTier(result.score)
        case .application, .file:
            if title == needle { return 0 }
            if title.hasPrefix(needle) { return 1 }
            if hasWordBoundary(needle, in: title) { return 2 }
            if title.contains(needle) { return 3 }
            if FuzzyMatcher.match(needle, in: title) != nil { return 4 }
            return baseTier(result.score)
        }
    }

    private static func hasWordBoundary(_ needle: String, in haystack: String) -> Bool {
        var start = haystack.startIndex
        while start < haystack.endIndex,
              let range = haystack.range(of: needle, range: start..<haystack.endIndex) {
            if range.lowerBound != haystack.startIndex {
                let previous = haystack[haystack.index(before: range.lowerBound)]
                if !previous.isLetter, !previous.isNumber {
                    return true
                }
            }
            start = range.upperBound
        }
        return false
    }

    private static func baseTier(_ score: Int) -> Int {
        if score >= 1000 { return 0 }
        if score >= 900 { return 1 }
        if score >= 800 { return 2 }
        if score >= 700 { return 3 }
        if score >= 500 { return 4 }
        return 5
    }

    private static func quality(forTier tier: Int) -> Double {
        switch tier {
        case 0, 1: return 1.0
        case 2: return 0.85
        case 3: return 0.65
        case 4: return 0.35
        default: return 0.2
        }
    }

    private static func intent(for query: String, results: [SearchResult]) -> Intent {
        let lower = query.lowercased()
        var intent = Intent()

        let websiteHosts = results
            .filter { $0.kind == .website }
            .map { $0.subtitle.lowercased() }

        if lower.contains("/") || lower.hasPrefix("~") {
            intent.files = 50
        } else if lower.contains(".") {
            if websiteHosts.contains(where: { $0.contains(lower) }) {
                intent.websites = 20
            } else {
                let ext = (lower as NSString).pathExtension
                intent.files = (!ext.isEmpty && ext.count <= 5) ? 45 : 25
            }
        }

        return intent
    }

    private func folderBoost(for result: SearchResult, now: Date) -> Double {
        guard result.kind == .file,
              let url = Self.fileURL(for: result) else { return 0 }
        let folder = url.deletingLastPathComponent().path
        guard let folders = data.recentFolders, !folders.isEmpty else { return 0 }

        var best = 0.0
        for entry in folders {
            let days = max(0.0, now.timeIntervalSince(entry.lastUsed) / 86_400.0)
            let decay = exp(-days / 7.0)
            if folder == entry.path {
                best = max(best, 30.0 * decay)
            } else if folder.hasPrefix(entry.path + "/") {
                best = max(best, 18.0 * decay)
            }
        }
        return best
    }

    private static func fileURL(for result: SearchResult) -> URL? {
        switch result.action {
        case .open(let url), .reveal(let url):
            return url.isFileURL ? url : nil
        case .run:
            return nil
        }
    }

    private static func noteFolder(for url: URL, date: Date, data: inout RankingData) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let folder = (isDirectory ? url : url.deletingLastPathComponent()).path
        guard !folder.isEmpty, folder != "/" else { return }

        var folders = data.recentFolders ?? []
        folders.removeAll { $0.path == folder }
        folders.insert(FolderUse(path: folder, lastUsed: date), at: 0)
        if folders.count > 8 {
            folders.removeLast(folders.count - 8)
        }
        data.recentFolders = folders
    }

    private static func timeBoost(_ usage: Usage, hourBucket: Int, isWeekend: Bool) -> Double {
        var boost = 0.0

        let hourTotal = usage.hourBuckets.reduce(0, +)
        if hourTotal >= 6, usage.hourBuckets.indices.contains(hourBucket) {
            let share = Double(usage.hourBuckets[hourBucket]) / Double(hourTotal)
            let baseline = 1.0 / 6.0
            if share > baseline {
                boost += min(10.0, (share - baseline) * 30.0)
            }
        }

        let dayTotal = usage.weekdayCount + usage.weekendCount
        if dayTotal >= 6 {
            let count = isWeekend ? usage.weekendCount : usage.weekdayCount
            let share = Double(count) / Double(dayTotal)
            let baseline = isWeekend ? 2.0 / 7.0 : 5.0 / 7.0
            if share > baseline {
                boost += min(6.0, (share - baseline) * 20.0)
            }
        }

        return boost
    }

    private static func affinity(_ usage: Usage, queryTokens: [String]) -> Double {
        guard !queryTokens.isEmpty else { return 0 }
        var total = 0
        for queryToken in queryTokens {
            for (stored, count) in usage.tokens
            where stored.hasPrefix(queryToken) || queryToken.hasPrefix(stored) {
                total += count
                break
            }
        }
        guard total > 0 else { return 0 }
        return min(40.0, 12.0 * log2(1.0 + Double(total)))
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "into",
        "der", "die", "das", "und", "für", "mit", "von", "den", "dem",
        "des", "ein", "eine", "einer", "eines", "auf", "aus", "bei",
        "mein", "meine", "meiner", "my", "mine"
    ]

    private static func tokens(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { token in
                token.count >= 3
                    && !stopwords.contains(token)
                    && seen.insert(token).inserted
            }
    }

    private static func dedupe(_ results: [SearchResult]) -> [SearchResult] {
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }

    private static func baseSort(_ results: [SearchResult]) -> [SearchResult] {
        results.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let leftKind = kindRank($0.kind)
            let rightKind = kindRank($1.kind)
            if leftKind != rightKind { return leftKind < rightKind }
            if $0.title.count != $1.title.count { return $0.title.count < $1.title.count }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func kindRank(_ kind: ResultKind) -> Int {
        switch kind {
        case .application: return 0
        case .command: return 1
        case .website: return 2
        case .file: return 3
        }
    }
}
