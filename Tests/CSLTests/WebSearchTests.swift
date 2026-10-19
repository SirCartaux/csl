import XCTest
import AppKit
@testable import CSL

final class WebSearchTests: XCTestCase {
    func testQuestionDetectionAndOrdinarySearch() {
        for text in ["Wie kann ich meinen Mac schneller machen?", "why is the sky blue", "Was bedeutet x in dieser Gleichung?", "das beste rezept für einen apfelkuchen", "google CSL", "g swift"] {
            XCTAssertNotNil(WebSearchProvider.result(for: text), text)
        }
        for text in ["Safari", "Visual Studio Code", "report.pdf", "/Users/me/My long folder name", "https://example.com/why is this", "y = x ^ 2", "f(x)=", "2 + 2 + 5", "sin(x) + x ^ 2", "google ", ""] {
            XCTAssertNil(WebSearchProvider.result(for: text), text)
        }
    }

    func testQueryIsEncodedAsOneParameter() throws {
        let question = "Wie funktionieren C++ & C# mit Größe + 2?"
        let result = try XCTUnwrap(WebSearchProvider.result(for: question))
        guard case .open(let url) = result.action else { return XCTFail("Expected a browser URL") }
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.path, "/search")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: question)])
        XCTAssertTrue(url.absoluteString.contains("%2B%2B"))
        XCTAssertFalse(url.absoluteString.contains("+"))
    }

    @MainActor
    func testQuestionProducesImmediateGoogleResultAndReturnsToSearch() {
        final class Delegate: SearchEngineDelegate {
            var results: [SearchResult] = []
            var searching = true
            func searchEngine(_ engine: SearchEngine, didUpdate results: [SearchResult], isSearching: Bool) {
                self.results = results; searching = isSearching
            }
        }
        let engine = SearchEngine(), delegate = Delegate()
        engine.delegate = delegate
        engine.search("Wie kann ich meinen Mac schneller machen?")
        XCTAssertEqual(delegate.results.count, 1)
        XCTAssertEqual(delegate.results.first?.title, "SEARCH GOOGLE")
        XCTAssertFalse(delegate.searching)
        engine.refreshIndexResults()
        XCTAssertEqual(delegate.results.count, 1)
        engine.search("")
        XCTAssertFalse(delegate.results.contains { $0.id.hasPrefix("google:") })
        engine.cancel()
    }

    @MainActor
    func testQuestionWithXDoesNotOpenGraph() {
        _ = NSApplication.shared
        let controller = SearchViewController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 764, height: 518)
        controller.setSearchText("Was bedeutet x in dieser Gleichung?")
        XCTAssertFalse((controller.view as! RootView).graphActive)
    }
}
