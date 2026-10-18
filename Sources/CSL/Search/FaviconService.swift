import AppKit

/// Loads a website's icon once in the background, then caches it as a PNG in
/// Application Support. Tries favicon/apple-touch-icon first and finally parses
/// the page's <link rel="icon"> tags.
final class FaviconService {
    static let shared = FaviconService()

    private let session: URLSession
    private var memory: [UUID: NSImage] = [:]
    private var inFlight: Set<UUID> = []
    private var failed: Set<UUID> = []

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration)
    }

    // MARK: - Cache

    func iconURL(for site: WebsiteEntry) -> URL? {
        guard let fileName = site.iconFileName else { return nil }
        let url = AppPaths.iconsDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func image(for site: WebsiteEntry) -> NSImage? {
        if let cached = memory[site.id] { return cached }
        guard let url = iconURL(for: site), let image = NSImage(contentsOf: url) else { return nil }
        memory[site.id] = image
        return image
    }

    func isLoading(_ site: WebsiteEntry) -> Bool {
        inFlight.contains(site.id)
    }

    func didFail(_ site: WebsiteEntry) -> Bool {
        failed.contains(site.id)
    }

    func retryIcon(for site: WebsiteEntry) {
        failed.remove(site.id)
        fetchIcon(for: site)
    }

    func removeIcon(for site: WebsiteEntry) {
        if let url = iconURL(for: site) {
            try? FileManager.default.removeItem(at: url)
        }
        memory.removeValue(forKey: site.id)
        failed.remove(site.id)
    }

    // MARK: - Fetching

    func prefetchMissing() {
        let missing = SettingsStore.shared.settings.websites.filter { iconURL(for: $0) == nil }
        for (index, site) in missing.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.35) { [weak self] in
                self?.fetchIcon(for: site)
            }
        }
    }

    func fetchIcon(for site: WebsiteEntry) {
        guard iconURL(for: site) == nil else { return }
        guard !inFlight.contains(site.id), !failed.contains(site.id) else { return }
        guard let pageURL = site.urlValue, let host = pageURL.host else { return }

        inFlight.insert(site.id)
        let scheme = pageURL.scheme ?? "https"
        let origin = "\(scheme)://\(host)"

        var candidates: [URL] = []
        if let touch = URL(string: origin + "/apple-touch-icon.png") { candidates.append(touch) }
        if let touch2 = URL(string: origin + "/apple-touch-icon-precomposed.png") { candidates.append(touch2) }
        if let favicon = URL(string: origin + "/favicon.ico") { candidates.append(favicon) }

        attempt(site: site, candidates: candidates, index: 0, tried: [], allowHTML: true)
    }

    private func attempt(site: WebsiteEntry, candidates: [URL], index: Int, tried: Set<String>, allowHTML: Bool) {
        guard index < candidates.count else {
            if allowHTML {
                fetchFromHTML(site: site, tried: tried)
            } else {
                fail(site: site)
            }
            return
        }

        let candidate = candidates[index]
        if tried.contains(candidate.absoluteString) {
            attempt(site: site, candidates: candidates, index: index + 1, tried: tried, allowHTML: allowHTML)
            return
        }

        var nextTried = tried
        nextTried.insert(candidate.absoluteString)
        download(candidate) { [weak self] data in
            guard let self else { return }
            if let data, let image = NSImage(data: data), image.size.width > 0 {
                self.finish(site: site, image: image)
            } else {
                self.attempt(
                    site: site,
                    candidates: candidates,
                    index: index + 1,
                    tried: nextTried,
                    allowHTML: allowHTML
                )
            }
        }
    }

    private func fetchFromHTML(site: WebsiteEntry, tried: Set<String>) {
        guard let pageURL = site.urlValue else {
            fail(site: site)
            return
        }

        download(pageURL) { [weak self] data in
            guard let self else { return }
            guard let data, data.count < 5_000_000,
                  let html = String(data: data, encoding: .utf8) else {
                self.fail(site: site)
                return
            }

            let candidates = Self.iconURLs(in: html, base: pageURL)
            guard !candidates.isEmpty else {
                self.fail(site: site)
                return
            }
            self.attempt(site: site, candidates: candidates, index: 0, tried: tried, allowHTML: false)
        }
    }

    private func download(_ url: URL, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let payload: Data?
            if error == nil, (200..<300).contains(status), let data, !data.isEmpty {
                payload = data
            } else {
                payload = nil
            }
            DispatchQueue.main.async { completion(payload) }
        }.resume()
    }

    private func finish(site: WebsiteEntry, image: NSImage) {
        inFlight.remove(site.id)
        guard let png = Self.pngData(from: image) else {
            fail(site: site)
            return
        }

        AppPaths.prepare()
        let fileName = site.id.uuidString + ".png"
        let url = AppPaths.iconsDirectory.appendingPathComponent(fileName)
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            Log.debug("favicon write failed: \(error)")
            fail(site: site)
            return
        }

        memory[site.id] = image
        IconCache.shared.invalidate(path: url.path)
        SettingsStore.shared.updateWebsiteIcon(id: site.id, fileName: fileName)
        NotificationCenter.default.post(
            name: .cslWebsiteIconUpdated,
            object: nil,
            userInfo: ["id": site.id, "success": true]
        )
        Log.debug("favicon loaded for \(site.host)")
    }

    private func fail(site: WebsiteEntry) {
        inFlight.remove(site.id)
        failed.insert(site.id)
        NotificationCenter.default.post(
            name: .cslWebsiteIconUpdated,
            object: nil,
            userInfo: ["id": site.id, "success": false]
        )
        Log.debug("favicon failed for \(site.host)")
    }

    // MARK: - Image processing

    private static func pngData(from image: NSImage) -> Data? {
        let maxSize: CGFloat = 64
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale = min(1, maxSize / max(sourceSize.width, sourceSize.height))
        let target = NSSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )

        let resized = NSImage(size: target, flipped: false) { rect in
            image.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: false,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }

        guard let tiff = resized.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }

    private static func iconURLs(in html: String, base: URL) -> [URL] {
        let source = html as NSString
        guard let tagRegex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]),
              let hrefRegex = try? NSRegularExpression(pattern: "href\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive])
        else { return [] }

        var urls: [URL] = []
        let fullRange = NSRange(location: 0, length: source.length)
        for match in tagRegex.matches(in: html, range: fullRange) {
            let tag = source.substring(with: match.range)
            guard tag.lowercased().contains("icon") else { continue }

            let tagSource = tag as NSString
            guard let hrefMatch = hrefRegex.firstMatch(in: tag, range: NSRange(location: 0, length: tagSource.length)) else {
                continue
            }
            let href = tagSource.substring(with: hrefMatch.range(at: 1))
            guard !href.hasPrefix("data:") else { continue }
            if let url = URL(string: href, relativeTo: base)?.absoluteURL {
                urls.append(url)
            }
        }
        return urls
    }
}
