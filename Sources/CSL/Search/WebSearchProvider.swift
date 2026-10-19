import Foundation

/// Recognize natural-language questions locally. No request is sent until Open.
enum WebSearchProvider {
    static func query(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000 else { return nil }
        let lower = text.lowercased()
        for prefix in ["google ", "g "] where lower.hasPrefix(prefix) {
            let explicit = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return explicit.isEmpty ? nil : explicit
        }
        let compact = lower.filter { !$0.isWhitespace }
        guard !compact.hasPrefix("y="), !compact.hasPrefix("f(x)="),
              (try? FunctionExpression(text)) == nil, Calculator.evaluate(text) == nil,
              !text.hasPrefix("/"), !text.hasPrefix("~"), !lower.contains("://") else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 3 else { return nil }
        let questionWords: Set<String> = ["wer", "wie", "was", "wann", "wo", "woher", "wohin", "warum", "wieso", "weshalb", "welche", "welcher", "welches", "kann", "können", "ist", "sind", "gibt", "hat", "haben", "how", "what", "why", "where", "when", "who", "which", "can", "does", "is", "are"]
        let first = String(words[0]).lowercased()
        guard text.hasSuffix("?") || questionWords.contains(first) || (words.count >= 5 && text.count >= 28) else { return nil }
        return text
    }

    static func result(for raw: String) -> SearchResult? {
        guard let query = query(from: raw) else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        // Google treats '+' as a form-encoded space; preserve literal C++ etc.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { return nil }
        return SearchResult(id: "google:"+query, title: "SEARCH GOOGLE", subtitle: query,
                            kind: .website, icon: .glyph(.globe), score: 1100, titleMatch: [], action: .open(url))
    }
}
