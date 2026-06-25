import AppKit
import Security

struct Connection {
    let id: UUID
    var name: String
    var uri: String
    var database: String
    var isConnected: Bool

    init(id: UUID = UUID(), name: String, uri: String, database: String, isConnected: Bool = false) {
        self.id = id
        self.name = name
        self.uri = uri
        self.database = database
        self.isConnected = isConnected
    }
}

struct StoredConnection: Codable {
    var id: UUID
    var name: String
    var database: String
}

struct DatabaseInfo: Decodable {
    var name: String
    var collections: [String]
}

enum MetadataResult {
    case success([DatabaseInfo])
    case failure(String)
}

final class TreeNode: NSObject {
    let title: String
    let connectionID: UUID?
    let database: String?
    var children: [TreeNode]

    init(_ title: String, connectionID: UUID? = nil, database: String? = nil, children: [TreeNode] = []) {
        self.title = title
        self.connectionID = connectionID
        self.database = database
        self.children = children
    }
}

final class Worksheet: NSObject {
    let id = UUID()
    var name: String
    let runner = MongoRunner()
    let targetPopup = NSPopUpButton()
    let databaseField = NSTextField()
    let modePopup = NSPopUpButton()
    let status = NSTextField(labelWithString: "Ready")
    let queryView: NSTextView
    let outputView: NSTextView
    let view: NSView
    private let panesView = NSView()
    private var queryHeightConstraint: NSLayoutConstraint?

    init(name: String, target: AnyObject, queryScroll: NSScrollView, queryView: NSTextView, outputScroll: NSScrollView, outputView: NSTextView) {
        self.name = name
        self.queryView = queryView
        self.outputView = outputView

        let root = NSView()
        root.setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.setContentHuggingPriority(.defaultLow, for: .vertical)
        self.view = root

        super.init()

        targetPopup.target = target
        targetPopup.action = #selector(AppDelegate.targetChanged)
        targetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        databaseField.placeholderString = "database"
        databaseField.stringValue = "test"
        databaseField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        modePopup.addItems(withTitles: ["JSON", "Shell"])

        let run = NSButton(title: "Run", target: target, action: #selector(AppDelegate.runQuery))
        run.bezelStyle = .rounded
        run.keyEquivalent = "\r"
        run.keyEquivalentModifierMask = [.command]

        let cancel = NSButton(title: "Cancel", target: target, action: #selector(AppDelegate.cancelQuery))
        cancel.bezelStyle = .rounded
        let save = NSButton(title: "Save", target: target, action: #selector(AppDelegate.saveWorksheet))
        save.bezelStyle = .rounded
        let load = NSButton(title: "Load", target: target, action: #selector(AppDelegate.loadWorksheet))
        load.bezelStyle = .rounded
        let saveOutput = NSButton(title: "Save Output", target: target, action: #selector(AppDelegate.saveOutput))
        saveOutput.bezelStyle = .rounded
        let clear = NSButton(title: "Clear", target: target, action: #selector(AppDelegate.clearOutput))
        clear.bezelStyle = .rounded

        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let targetRow = NSStackView(views: [targetPopup, databaseField, modePopup, status])
        targetRow.orientation = .horizontal
        targetRow.spacing = 8
        targetRow.alignment = .centerY
        targetRow.setContentHuggingPriority(.required, for: .vertical)
        targetRow.setContentCompressionResistancePriority(.required, for: .vertical)

        let actionRow = NSStackView(views: [run, cancel, save, load, saveOutput, clear])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8
        actionRow.alignment = .centerY
        actionRow.setContentHuggingPriority(.required, for: .vertical)
        actionRow.setContentCompressionResistancePriority(.required, for: .vertical)

        let toolbar = NSStackView(views: [targetRow, actionRow])
        toolbar.orientation = .vertical
        toolbar.spacing = 8
        toolbar.alignment = .leading
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.setContentHuggingPriority(.required, for: .vertical)
        toolbar.setContentCompressionResistancePriority(.required, for: .vertical)

        let queryPane = Worksheet.pane(label: "Worksheet", scroll: queryScroll)
        let outputPane = Worksheet.pane(label: "Output", scroll: outputScroll)
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(resizeOutput(_:))))

        panesView.translatesAutoresizingMaskIntoConstraints = false
        queryPane.translatesAutoresizingMaskIntoConstraints = false
        outputPane.translatesAutoresizingMaskIntoConstraints = false
        panesView.addSubview(queryPane)
        panesView.addSubview(divider)
        panesView.addSubview(outputPane)

        queryHeightConstraint = queryPane.heightAnchor.constraint(equalToConstant: 300)
        queryHeightConstraint?.isActive = true

        root.addSubview(toolbar)
        root.addSubview(panesView)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -8),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            panesView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            panesView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            panesView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            panesView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            queryPane.leadingAnchor.constraint(equalTo: panesView.leadingAnchor),
            queryPane.trailingAnchor.constraint(equalTo: panesView.trailingAnchor),
            queryPane.topAnchor.constraint(equalTo: panesView.topAnchor),
            divider.leadingAnchor.constraint(equalTo: panesView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: panesView.trailingAnchor),
            divider.topAnchor.constraint(equalTo: queryPane.bottomAnchor, constant: 6),
            divider.heightAnchor.constraint(equalToConstant: 5),
            outputPane.leadingAnchor.constraint(equalTo: panesView.leadingAnchor),
            outputPane.trailingAnchor.constraint(equalTo: panesView.trailingAnchor),
            outputPane.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
            outputPane.bottomAnchor.constraint(equalTo: panesView.bottomAnchor),
            outputPane.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
    }

    func setInitialDividerPosition() {
        view.layoutSubtreeIfNeeded()
        panesView.layoutSubtreeIfNeeded()
        let height = panesView.bounds.height
        guard height > 420 else { return }
        queryHeightConstraint?.constant = height * 0.48
    }

    @objc private func resizeOutput(_ gesture: NSPanGestureRecognizer) {
        guard let constraint = queryHeightConstraint else { return }
        let translation = gesture.translation(in: panesView)
        let proposed = constraint.constant + translation.y
        let maxHeight = max(220, panesView.bounds.height - 180)
        constraint.constant = min(max(proposed, 180), maxHeight)
        gesture.setTranslation(.zero, in: panesView)
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 12)
        return label
    }

    private static func pane(label text: String, scroll: NSScrollView) -> NSView {
        let view = NSView()
        let label = Worksheet.label(text)
        label.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return view
    }
}

enum ConnectionStore {
    private static let defaultsKey = "connections"
    private static let service = "MongoDBClient.ConnectionURI"

    static func load() -> [Connection] {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let stored = try? JSONDecoder().decode([StoredConnection].self, from: data)
        else { return [] }

        return stored.compactMap { item in
            guard let uri = keychainValue(account: item.id.uuidString) else { return nil }
            return Connection(id: item.id, name: item.name, uri: uri, database: item.database, isConnected: false)
        }
    }

    static func save(_ connections: [Connection]) {
        let stored = connections.map { StoredConnection(id: $0.id, name: $0.name, database: $0.database) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        for connection in connections {
            setKeychainValue(connection.uri, account: connection.id.uuidString)
        }
    }

    static func delete(_ connection: Connection) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connection.id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func keychainValue(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func setKeychainValue(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

final class MongoRunner {
    private var process: Process?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func cancel() {
        process?.terminate()
    }

    func run(uri: String, database: String, query: String, json: Bool, completion: @escaping (String) -> Void) {
        cancel()

        let proc = Process()
        let out = Pipe()
        let err = Pipe()
        let command = mongoshCommand(arguments: [targetURI(uri: uri, database: database), "--quiet", "--eval", script(for: query, json: json)])
        proc.executableURL = command.executable
        proc.arguments = command.arguments
        proc.standardOutput = out
        proc.standardError = err
        process = proc

        proc.terminationHandler = { [weak self] process in
            let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errors = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let text = [output, errors].filter { !$0.isEmpty }.joined(separator: "\n")
            DispatchQueue.main.async {
                if self?.process === process {
                    self?.process = nil
                }
                completion(text.isEmpty ? "(no output)" : text)
            }
        }

        do {
            try proc.run()
        } catch {
            process = nil
            completion("Could not start mongosh: \(error.localizedDescription)\nInstall mongosh and make sure it is in PATH.")
        }
    }

    func listDatabases(uri: String, completion: @escaping (MetadataResult) -> Void) {
        let proc = Process()
        let out = Pipe()
        let err = Pipe()
        let command = mongoshCommand(arguments: [targetURI(uri: uri, database: "admin"), "--quiet", "--eval", """
        (async () => {
          const names = (await db.adminCommand({ listDatabases: 1, nameOnly: true })).databases.map(d => d.name).sort();
          const result = [];
          for (const name of names.sort()) {
            try {
              const batch = (await db.getSiblingDB(name).runCommand({ listCollections: 1, nameOnly: true })).cursor.firstBatch;
              result.push({ name, collections: batch.map(c => c.name).sort() });
            } catch (e) {
              result.push({ name, collections: [`<error: ${e.message}>`] });
            }
          }
          console.log(JSON.stringify(result));
        })().catch(e => { console.error(e); process.exit(1); })
        """])
        proc.executableURL = command.executable
        proc.arguments = command.arguments
        proc.standardOutput = out
        proc.standardError = err
        proc.terminationHandler = { process in
            let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errors = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard process.terminationStatus == 0 else {
                    completion(.failure(errors.isEmpty ? output : errors))
                    return
                }
                let json = output.split(whereSeparator: \.isNewline).last.map(String.init) ?? output
                guard let data = json.data(using: .utf8),
                      let dbs = try? JSONDecoder().decode([DatabaseInfo].self, from: data) else {
                    completion(.failure(output.isEmpty ? "No database metadata returned." : output))
                    return
                }
                completion(.success(dbs))
            }
        }

        do {
            try proc.run()
        } catch {
            completion(.failure("Could not start mongosh: \(error.localizedDescription)"))
        }
    }

    private func script(for query: String, json: Bool) -> String {
        if json {
            return """
            (async () => {
              const value = await (async () => { return \(query); })();
              if (value && typeof value.toArray === 'function') {
                console.log(EJSON.stringify(await value.toArray(), null, 2));
              } else {
                console.log(EJSON.stringify(value, null, 2));
              }
            })().catch(e => { console.error(e); process.exit(1); })
            """
        }

        return """
        (async () => {
          const value = await (async () => { \(query) })();
          if (value !== undefined) console.log(value);
        })().catch(e => { console.error(e); process.exit(1); })
        """
    }

    private func mongoshCommand(arguments: [String]) -> (executable: URL, arguments: [String]) {
        for path in ["/opt/homebrew/bin/mongosh", "/usr/local/bin/mongosh", "/usr/bin/mongosh"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return (URL(fileURLWithPath: path), arguments)
            }
        }

        return (
            URL(fileURLWithPath: "/usr/bin/env"),
            ["PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "mongosh"] + arguments
        )
    }

    private func targetURI(uri: String, database: String) -> String {
        let db = database.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !db.isEmpty else { return uri }

        let parts = uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var base = String(parts[0])
        let query = parts.count == 2 ? "?\(parts[1])" : ""
        let afterScheme = base.split(separator: "://", maxSplits: 1, omittingEmptySubsequences: false).last.map(String.init) ?? base

        if let slash = afterScheme.firstIndex(of: "/") {
            let path = afterScheme[slash...]
            if path == "/" {
                if base.hasSuffix("/") {
                    base.removeLast()
                }
                return "\(base)/\(db)\(query)"
            }
            return uri
        }

        if base.hasSuffix("/") {
            base.removeLast()
        }
        return "\(base)/\(db)\(query)"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSplitViewDelegate {
    private var window: NSWindow!
    private var connections: [Connection] = []
    private var treeRoots: [TreeNode] = []
    private var worksheets: [Worksheet] = []

    private let table = NSTableView()
    private let outline = NSOutlineView()
    private let mainSplit = NSSplitView()
    private let tabView = NSTabView()
    private let metadataRunner = MongoRunner()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        connections = ConnectionStore.load()
        buildWindow()
        addWorksheet()
        table.reloadData()
        rebuildTargets(selecting: connectedConnections().first?.id)
        refreshTree()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            self.mainSplit.setPosition(320, ofDividerAt: 0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        connections.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let suffix = connections[row].isConnected ? "" : " (disconnected)"
        let cell = NSTextField(labelWithString: connections[row].name + suffix)
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard connections.indices.contains(row) else { return }
        if connections[row].isConnected {
            selectConnection(row)
        } else {
            currentWorksheet?.status.stringValue = "Profile disconnected: \(connections[row].name)"
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? TreeNode)?.children.count ?? treeRoots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? TreeNode)?.children[index] ?? treeRoots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? TreeNode)?.children.isEmpty == false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as? TreeNode
        let cell = NSTextField(labelWithString: node?.title ?? "")
        cell.lineBreakMode = .byClipping
        cell.toolTip = node?.title
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let node = outline.item(atRow: outline.selectedRow) as? TreeNode,
              let connectionID = node.connectionID,
              let index = connections.firstIndex(where: { $0.id == connectionID }) else { return }
        currentWorksheet?.targetPopup.selectItem(at: index)
        selectConnection(index)
        if let database = node.database {
            currentWorksheet?.databaseField.stringValue = database
        }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        240
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(240, min(600, splitView.bounds.width - 520))
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MongoDB Client"
        window.center()

        let root = mainSplit
        root.isVertical = true
        root.dividerStyle = .thin
        root.delegate = self
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])

        let side = sidebar()
        let work = workspace()
        work.setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(side)
        root.addArrangedSubview(work)
        root.setPosition(320, ofDividerAt: 0)
    }

    private func sidebar() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let title = NSTextField(labelWithString: "Connections")
        title.font = .boldSystemFont(ofSize: 14)
        title.alignment = .left
        title.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = table
        table.headerView = nil
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        table.delegate = self
        table.dataSource = self

        let add = button("Add", #selector(addConnection))
        let connect = button("Connect", #selector(connectConnection))
        let disconnect = button("Disconnect", #selector(disconnectConnection))
        let remove = button("Remove", #selector(removeConnection))
        let buttons = row([add, connect, disconnect, remove])
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let refresh = button("Refresh", #selector(refreshTree))
        let treeTitle = row([label("Databases"), refresh])
        treeTitle.translatesAutoresizingMaskIntoConstraints = false
        let treeScroll = NSScrollView()
        treeScroll.hasVerticalScroller = true
        treeScroll.hasHorizontalScroller = true
        treeScroll.borderType = .bezelBorder
        treeScroll.translatesAutoresizingMaskIntoConstraints = false
        treeScroll.documentView = outline
        outline.headerView = nil
        let treeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        treeColumn.width = 900
        outline.addTableColumn(treeColumn)
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.columnAutoresizingStyle = .noColumnAutoresizing
        outline.delegate = self
        outline.dataSource = self

        for child in [title, scroll, buttons, treeTitle, treeScroll] {
            view.addSubview(child)
        }

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            scroll.heightAnchor.constraint(equalToConstant: 96),
            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            treeTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            treeTitle.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            treeTitle.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 12),
            treeScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            treeScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            treeScroll.topAnchor.constraint(equalTo: treeTitle.bottomAnchor, constant: 8),
            treeScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
        return view
    }

    private func workspace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let newWorksheet = button("New Worksheet", #selector(addWorksheet))
        let closeWorksheet = button("Close Worksheet", #selector(closeWorksheet))
        let controls = row([newWorksheet, closeWorksheet])
        controls.translatesAutoresizingMaskIntoConstraints = false

        tabView.tabViewType = .topTabsBezelBorder
        tabView.drawsBackground = false
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabView.setContentHuggingPriority(.defaultLow, for: .vertical)

        view.addSubview(controls)
        view.addSubview(tabView)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            controls.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tabView.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            tabView.heightAnchor.constraint(greaterThanOrEqualToConstant: 620)
        ])
        return view
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        return stack
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 12)
        label.alignment = .left
        return label
    }

    private var currentWorksheet: Worksheet? {
        guard let item = tabView.selectedTabViewItem else { return nil }
        return worksheets.first { $0.id.uuidString == item.identifier as? String }
    }

    @objc func addWorksheet() {
        let number = worksheets.count + 1
        let query = textEditor(initialText: "db.getCollectionNames()", editable: true)
        let output = textEditor(initialText: "", editable: false)
        let worksheet = Worksheet(
            name: "Worksheet \(number)",
            target: self,
            queryScroll: query.scroll,
            queryView: query.text,
            outputScroll: output.scroll,
            outputView: output.text
        )

        worksheets.append(worksheet)
        populateTargets(for: worksheet, selecting: connectedConnections().first?.id)

        let item = NSTabViewItem(identifier: worksheet.id.uuidString)
        item.label = worksheet.name
        item.view = worksheet.view
        tabView.addTabViewItem(item)
        tabView.selectTabViewItem(item)
        DispatchQueue.main.async {
            worksheet.setInitialDividerPosition()
        }
    }

    @objc func closeWorksheet() {
        guard worksheets.count > 1,
              let item = tabView.selectedTabViewItem,
              let id = item.identifier as? String,
              let index = worksheets.firstIndex(where: { $0.id.uuidString == id }) else { return }
        worksheets[index].runner.cancel()
        worksheets.remove(at: index)
        tabView.removeTabViewItem(item)
    }

    private func textEditor(initialText: String, editable: Bool) -> (scroll: NSScrollView, text: NSTextView) {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true

        let textView = scroll.documentView as! NSTextView
        textView.string = initialText
        textView.isEditable = editable
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        return (scroll, textView)
    }

    private func populateTargets(for worksheet: Worksheet, selecting selectedID: UUID?) {
        worksheet.targetPopup.removeAllItems()
        let active = connectedConnections()
        guard !active.isEmpty else {
            worksheet.targetPopup.addItem(withTitle: "No connection")
            worksheet.status.stringValue = "Disconnected"
            return
        }

        for connection in active {
            worksheet.targetPopup.addItem(withTitle: connection.name)
        }

        let selectedIndex = selectedID.flatMap { id in active.firstIndex { $0.id == id } } ?? 0
        worksheet.targetPopup.selectItem(at: selectedIndex)
        worksheet.databaseField.stringValue = active[selectedIndex].database
        worksheet.status.stringValue = "Connected: \(active[selectedIndex].name)"
    }

    private func connectedConnections() -> [Connection] {
        connections.filter(\.isConnected)
    }

    private func selectedConnectedConnection(for worksheet: Worksheet) -> (index: Int, connection: Connection)? {
        let active = connectedConnections()
        let selected = worksheet.targetPopup.indexOfSelectedItem
        guard active.indices.contains(selected),
              let index = connections.firstIndex(where: { $0.id == active[selected].id }) else { return nil }
        return (index, active[selected])
    }

    @objc private func addConnection() {
        let alert = NSAlert()
        alert.messageText = "Add MongoDB Connection"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let form = NSStackView()
        form.orientation = .vertical
        form.spacing = 8
        form.frame = NSRect(x: 0, y: 0, width: 520, height: 96)

        let name = field("Name", "local")
        let uri = field("URI", "mongodb://localhost:27017")
        let db = field("Database", "test")
        form.addArrangedSubview(name)
        form.addArrangedSubview(uri)
        form.addArrangedSubview(db)
        alert.accessoryView = form

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let connection = Connection(name: name.stringValue, uri: uri.stringValue, database: db.stringValue, isConnected: false)
        connections.append(connection)
        ConnectionStore.save(connections)
        table.reloadData()
        rebuildTargets(selecting: connectedConnections().first?.id)
        refreshTree()
        currentWorksheet?.status.stringValue = "Saved profile: \(connection.name)"
    }

    private func field(_ placeholder: String, _ value: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        return field
    }

    @objc private func disconnectConnection() {
        let row = table.selectedRow
        guard connections.indices.contains(row) else { return }
        connections[row].isConnected = false
        table.reloadData()
        rebuildTargets(selecting: connectedConnections().first?.id)
        refreshTree()
        currentWorksheet?.status.stringValue = "Disconnected: \(connections[row].name)"
    }

    @objc private func connectConnection() {
        let row = table.selectedRow
        guard connections.indices.contains(row) else { return }
        connections[row].isConnected = true
        table.reloadData()
        rebuildTargets(selecting: connections[row].id)
        refreshTree()
        currentWorksheet?.status.stringValue = "Connected: \(connections[row].name)"
    }

    @objc private func removeConnection() {
        let row = table.selectedRow
        guard connections.indices.contains(row) else { return }
        let removed = connections.remove(at: row)
        ConnectionStore.delete(removed)
        ConnectionStore.save(connections)
        table.reloadData()
        rebuildTargets(selecting: connectedConnections().first?.id)
        refreshTree()
        currentWorksheet?.status.stringValue = "Removed: \(removed.name)"
    }

    @objc private func refreshTree() {
        let active = connectedConnections()
        guard !active.isEmpty else {
            treeRoots = [TreeNode(connections.isEmpty ? "No connections" : "No connected profiles")]
            outline.reloadData()
            currentWorksheet?.status.stringValue = connections.isEmpty ? "Add a connection to load databases" : "Connect a profile to load databases"
            return
        }

        treeRoots = active.map {
            TreeNode($0.name, connectionID: $0.id, children: [TreeNode("Loading...")])
        }
        outline.reloadData()
        for root in treeRoots {
            outline.expandItem(root)
        }

        for connection in active {
            metadataRunner.listDatabases(uri: connection.uri) { [weak self] result in
                guard let self,
                      let root = self.treeRoots.first(where: { $0.connectionID == connection.id }) else { return }

                switch result {
                case .success(let databases):
                    root.children = databases.map { database in
                        TreeNode(
                            database.name,
                            connectionID: connection.id,
                            database: database.name,
                            children: database.collections.map {
                                TreeNode($0, connectionID: connection.id, database: database.name)
                            }
                        )
                    }
                case .failure(let message):
                    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                    root.children = [TreeNode(trimmed.isEmpty ? "Could not load databases" : trimmed)]
                }

                self.outline.reloadData()
                self.outline.expandItem(root)
                self.currentWorksheet?.status.stringValue = root.children.isEmpty ? "No databases found" : "Database tree refreshed"
            }
        }
    }

    @objc func targetChanged() {
        guard let worksheet = currentWorksheet else { return }
        guard let selected = selectedConnectedConnection(for: worksheet) else { return }
        selectConnection(selected.index)
    }

    private func selectConnection(_ index: Int) {
        guard connections.indices.contains(index) else { return }
        if table.selectedRow != index {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        currentWorksheet?.databaseField.stringValue = connections[index].database
        currentWorksheet?.status.stringValue = "Connected: \(connections[index].name)"
    }

    private func rebuildTargets(selecting selectedID: UUID?) {
        for worksheet in worksheets {
            let currentID = selectedConnectedConnection(for: worksheet)?.connection.id
            populateTargets(for: worksheet, selecting: selectedID ?? currentID)
        }

        if let id = selectedID, let index = connections.firstIndex(where: { $0.id == id }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if connections.isEmpty {
            table.deselectAll(nil)
        }
    }

    @objc func runQuery() {
        guard let worksheet = currentWorksheet else { return }
        guard let selected = selectedConnectedConnection(for: worksheet) else {
            worksheet.outputView.string = "Add a connection first."
            return
        }

        var connection = selected.connection
        connection.database = worksheet.databaseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        connections[selected.index] = connection
        ConnectionStore.save(connections)
        table.reloadData()

        worksheet.status.stringValue = "Running..."
        let json = worksheet.modePopup.titleOfSelectedItem == "JSON"
        worksheet.runner.run(uri: connection.uri, database: connection.database, query: worksheet.queryView.string, json: json) { [weak worksheet] text in
            worksheet?.outputView.string = text
            worksheet?.status.stringValue = "Done"
        }
    }

    @objc func cancelQuery() {
        currentWorksheet?.runner.cancel()
        currentWorksheet?.status.stringValue = "Cancelled"
    }

    @objc func clearOutput() {
        currentWorksheet?.outputView.string = ""
    }

    @objc func saveOutput() {
        guard let worksheet = currentWorksheet else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json, .plainText]
        panel.nameFieldStringValue = "output.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try worksheet.outputView.string.write(to: url, atomically: true, encoding: .utf8)
            worksheet.status.stringValue = "Output saved"
        } catch {
            worksheet.outputView.string = error.localizedDescription
        }
    }

    @objc func saveWorksheet() {
        guard let worksheet = currentWorksheet else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.javaScript]
        panel.nameFieldStringValue = "worksheet.mongo.js"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try worksheet.queryView.string.write(to: url, atomically: true, encoding: .utf8)
            worksheet.status.stringValue = "Saved"
        } catch {
            worksheet.outputView.string = error.localizedDescription
        }
    }

    @objc func loadWorksheet() {
        guard let worksheet = currentWorksheet else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.javaScript, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            worksheet.queryView.string = try String(contentsOf: url, encoding: .utf8)
            worksheet.status.stringValue = "Loaded"
        } catch {
            worksheet.outputView.string = error.localizedDescription
        }
    }
}

private func installMainMenu() {
    let main = NSMenu()

    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit MongoDB Client", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appMenuItem.submenu = appMenu
    main.addItem(appMenuItem)

    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenuItem.submenu = editMenu
    main.addItem(editMenuItem)

    NSApp.mainMenu = main
}

let app = NSApplication.shared
installMainMenu()
let delegate = AppDelegate()
app.delegate = delegate
app.run()
