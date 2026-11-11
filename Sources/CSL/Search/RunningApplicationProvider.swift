import AppKit

struct RunningProgram {
    let processID: pid_t
    let name: String
    let bundleURL: URL
    let launchDate: Date?

    init?(application: NSRunningApplication) {
        guard application.activationPolicy == .regular,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated,
              let url = application.bundleURL else { return nil }
        processID = application.processIdentifier
        name = application.localizedName ?? url.deletingPathExtension().lastPathComponent
        bundleURL = url
        launchDate = application.launchDate
    }

    init(processID: pid_t, name: String, bundleURL: URL, launchDate: Date? = nil) {
        self.processID = processID
        self.name = name
        self.bundleURL = bundleURL
        self.launchDate = launchDate
    }
}

/// No timer, workspace observer or process snapshot exists outside task mode.
/// While active, keystrokes only filter the cached list; workspace events refresh it.
final class RunningApplicationProvider {
    private let snapshot: () -> [RunningProgram]
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var programs: [RunningProgram] = []
    private(set) var isActive = false
    var onChange: (() -> Void)?

    init(snapshot: @escaping () -> [RunningProgram] = {
        NSWorkspace.shared.runningApplications.compactMap(RunningProgram.init(application:))
    }, center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.snapshot = snapshot
        self.center = center
    }

    func results(command: ProcessCommand, query: String) -> [SearchResult] {
        if !isActive {
            isActive = true
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    guard let self, self.isActive else { return }
                    self.programs = self.snapshot()
                    self.onChange?()
                })
            }
            programs = snapshot()
        }
        return Self.results(programs: programs, command: command, query: query)
    }

    static func results(programs: [RunningProgram], command: ProcessCommand, query: String) -> [SearchResult] {
        programs.compactMap { program -> SearchResult? in
            let match = query.isEmpty ? nil : FuzzyMatcher.match(query, in: program.name)
            guard query.isEmpty || match != nil else { return nil }
            return SearchResult(
                id: "process:\(command.rawValue):\(program.processID):\(program.launchDate?.timeIntervalSince1970 ?? 0)",
                title: program.name,
                subtitle: "\(command.label) APP · PID \(program.processID)",
                kind: .command, icon: .file(program.bundleURL), score: match?.score ?? 0,
                titleMatch: match?.ranges ?? [], action: .manage(command, program),
                shortcut: ShortcutPresentation(prefix: command.label, name: command.label, tint: command.tint)
            )
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let comparison = $0.title.localizedCaseInsensitiveCompare($1.title)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    func stop() {
        observers.forEach(center.removeObserver)
        observers.removeAll()
        programs.removeAll()
        isActive = false
    }

    deinit { observers.forEach(center.removeObserver) }
}

@MainActor
enum ProcessActionRunner {
    struct Target {
        let isTerminated: () -> Bool
        let terminate: () -> Bool
    }

    struct Environment {
        let resolve: (RunningProgram) -> Target?
        let launch: (URL) async -> Bool

        static var live: Environment {
            Environment(resolve: { program in
                guard let launchDate = program.launchDate,
                      let application = NSRunningApplication(processIdentifier: program.processID),
                      !application.isTerminated,
                      application.bundleURL == program.bundleURL,
                      application.launchDate == launchDate,
                      application.activationPolicy == .regular,
                      application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
                return Target(isTerminated: { application.isTerminated }, terminate: { application.terminate() })
            }, launch: { url in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                return await withCheckedContinuation { continuation in
                    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                        continuation.resume(returning: application != nil && error == nil)
                    }
                }
            })
        }
    }

    /// A quit request is not an exit. Wait without blocking AppKit, and never
    /// relaunch after a cancelled save dialog or a refused/timed-out quit.
    static func run(_ command: ProcessCommand, program: RunningProgram,
                    environment: Environment = .live, timeout: Duration = .seconds(30)) async -> Bool {
        guard !Task.isCancelled, let target = environment.resolve(program), target.terminate() else { return false }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !target.isTerminated() {
            guard !Task.isCancelled, ContinuousClock.now < deadline else { return false }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return false }
        }
        guard !Task.isCancelled else { return false }
        if command == .restart { return await environment.launch(program.bundleURL) }
        return true
    }
}
