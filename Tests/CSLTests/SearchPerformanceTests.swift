import XCTest
@testable import CSL

final class SearchPerformanceTests: XCTestCase {
    static let entries: [IndexedFile] = (0..<30000).map { i in
        let name = i % 97 == 0 ? "Project Report \(i).pdf" : "Document \(i).txt"
        let folder = i % 23 == 0 ? "/fixture/node_modules" : (i % 31 == 0 ? "/fixture/private" : "/fixture/Documents")
        return IndexedFile(path: "\(folder)/\(name)", name: name, lowerName: name.lowercased(), isDirectory: false, ext: i % 97 == 0 ? "pdf" : "txt", root: "/fixture")
    }

    func testIndexScanBenchmark() {
        let entries = Self.entries
        for query in ["report", "document", "missing-needle"] {
            var times: [Double] = []
            var count = 0
            for _ in 0..<3 {
                let start = Date()
                let results = FileIndex.search(entries, needle: query, ignoredFolders: ["/fixture/private"], ignoredExtensions: [], limit: Int.max, isCancelled: { false })
                times.append(Date().timeIntervalSince(start)*1000)
                count = results.count
            }
            print(String(format: "SCAN BENCH %@: %.2f ms median, %d results / %d files", query, times.sorted()[1], count, entries.count))
        }
    }

    @MainActor
    func testCancelledSearchDoesNotDeliverStaleCallbacks() async {
        let index = FileIndex(initialEntries: Self.entries)
        var staleUpdates = 0
        index.searchAsync(for: "document", progress: { _, _ in staleUpdates += 1 },
                          batch: { _ in staleUpdates += 1 }, completion: { _ in staleUpdates += 1 })
        // Clearing the field must cancel work even though the replacement query
        // is too short to start another scan.
        index.searchAsync(for: "d") { XCTAssertTrue($0.isEmpty) }
        index.cancelSearch()
        let latest = expectation(description: "latest query completes")
        var streamed = Set<String>()
        index.searchAsync(for: "report", batch: { batch in
            for result in batch { streamed.insert(result.id) }
        }) { results in
            XCTAssertFalse(results.isEmpty)
            XCTAssertEqual(streamed, Set(results.map(\.id)))
            XCTAssertEqual(staleUpdates, 0)
            latest.fulfill()
        }
        await fulfillment(of: [latest], timeout: 3)
        XCTAssertEqual(staleUpdates, 0)
    }

    func testPathExclusionsMatchOriginalRules() {
        let components = ["build", "BUILD", "builder", "node_modules", ".git", "cmake-build-debug", "cmake-build-", "cmake-build", "Überblick", "Library", "library-file", "cache", "caches", "file.txt", ""]
        for a in components {
            for b in components {
                for path in ["/Users/test/\(a)/\(b)", "\(a)/\(b)", "/\(a)//\(b)/", "/\(a)"] {
                    let expected = SearchExclusions.fragments.contains { path.lowercased().contains($0) }
                    XCTAssertEqual(SearchExclusions.isExcluded(path), expected, path)
                }
            }
        }
    }

    func testIndexFilteringAndScoring() {
        let cases = ["Report.pdf", "Project Report.pdf", "Ä report.pdf", "myreport.pdf", "REPORT.txt", "報告 report.pdf"]
        let entries = cases.enumerated().map { i, name in
            IndexedFile(path: "/fixture/\(i)/\(name)", name: name, lowerName: name.lowercased(), isDirectory: false, ext: (name as NSString).pathExtension, root: "/fixture")
        } + [IndexedFile(path: "/fixture/node_modules/Report.pdf", name: "Report.pdf", lowerName: "report.pdf", isDirectory: false, ext: "pdf", root: "/fixture"),
             IndexedFile(path: "/fixture/private/Report.pdf", name: "Report.pdf", lowerName: "report.pdf", isDirectory: false, ext: "pdf", root: "/fixture")]
        let results = FileIndex.search(entries, needle: "report", ignoredFolders: ["/fixture/private"], ignoredExtensions: ["txt"], limit: Int.max, isCancelled: { false })
        XCTAssertEqual(Set(results.map(\.title)), Set(["Report.pdf", "Project Report.pdf", "Ä report.pdf", "報告 report.pdf"]))
        XCTAssertEqual(results.first?.title, "Report.pdf")
        XCTAssertEqual(results.first?.score, 912)
        XCTAssertEqual(results.first?.titleMatch, [NSRange(location:0,length:6)])
        XCTAssertTrue(FileIndex.search(Self.entries, needle: "document", ignoredFolders: [], ignoredExtensions: [], limit: Int.max, isCancelled: { true }).isEmpty)
    }
}
