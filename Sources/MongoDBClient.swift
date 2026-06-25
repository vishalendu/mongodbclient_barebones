import AppKit
import Security

struct Connection {
    let id: UUID
    var name: String
    var uri: String
    var database: String

    init(id: UUID = UUID(), name: String, uri: String, database: String) {
        self.id = id
        self.name = name
        self.uri = uri
        self.database = database
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
            return Connection(id: item.id, name: item.name, uri: uri, database: item.database)
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
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["mongosh", targetURI(uri: uri, database: database), "--quiet", "--eval", script(for: query, json: json)]
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
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["mongosh", targetURI(uri: uri, database: "admin"), "--quiet", "--eval", """
        (async () => {
          const names = await db.getMongo().getDBNames();
          const result = [];
          for (const name of names.sort()) {
            result.push({ name, collections: (await db.getSiblingDB(name).getCollectionNames()).sort() });
          }
          console.log(JSON.stringify(result));
        })().catch(e => { console.error(e); process.exit(1); })
        """]
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
                guard let data = output.data(using: .utf8),
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

    private func targetURI(uri: String, database: String) -> String {
        let db = database.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !db.isEmpty else { return uri }

        let parts = uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var base = String(parts[0])
        let query = parts.count == 2 ? "?\(parts[1])" : ""
        let afterScheme = base.split(separator: "://", maxSplits: 1, omittingEmptySubsequences: false).last.map(String.init) ?? base

        if afterScheme.contains("/") {
            return uri
        }

        if base.hasSuffix("/") {
            base.removeLast()
        }
        return "\(base)/\(db)\(query)"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private var window: NSWindow!
    private let runner = MongoRunner()
    private var connections: [Connection] = []
    private var treeRoots: [TreeNode] = []

    private let table = NSTableView()
    private let outline = NSOutlineView()
    private let targetPopup = NSPopUpButton()
    private let databaseField = NSTextField()
    private let modePopup = NSPopUpButton()
    private let status = NSTextField(labelWithString: "Disconnected")
    private let queryView = NSTextView()
    private let outputView = NSTextView()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        connections = ConnectionStore.load()
        table.reloadData()
        rebuildTargets(selecting: connections.first?.id)
        refreshTree()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        connections.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: connections[row].name)
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectConnection(table.selectedRow)
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
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let node = outline.item(atRow: outline.selectedRow) as? TreeNode,
              let connectionID = node.connectionID,
              let index = connections.firstIndex(where: { $0.id == connectionID }) else { return }
        targetPopup.selectItem(at: index)
        selectConnection(index)
        if let database = node.database {
            databaseField.stringValue = database
        }
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

        let root = NSStackView()
        root.orientation = .horizontal
        root.spacing = 0
        root.distribution = .fill
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
    }

    private func sidebar() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = 8
        view.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.widthAnchor.constraint(equalToConstant: 250).isActive = true

        let title = NSTextField(labelWithString: "Connections")
        title.font = .boldSystemFont(ofSize: 14)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 130).isActive = true
        scroll.documentView = table
        table.headerView = nil
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        table.delegate = self
        table.dataSource = self

        let add = button("Add", #selector(addConnection))
        let remove = button("Disconnect", #selector(disconnectConnection))
        let buttons = row([add, remove])

        let refresh = button("Refresh", #selector(refreshTree))
        let treeTitle = row([label("Databases"), refresh])
        let treeScroll = NSScrollView()
        treeScroll.hasVerticalScroller = true
        treeScroll.borderType = .bezelBorder
        treeScroll.documentView = outline
        outline.headerView = nil
        outline.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.delegate = self
        outline.dataSource = self

        view.addArrangedSubview(title)
        view.addArrangedSubview(scroll)
        view.addArrangedSubview(buttons)
        view.addArrangedSubview(treeTitle)
        view.addArrangedSubview(treeScroll)
        return view
    }

    private func workspace() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = 8
        view.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        targetPopup.target = self
        targetPopup.action = #selector(targetChanged)
        targetPopup.addItem(withTitle: "No connection")

        databaseField.placeholderString = "database"
        databaseField.stringValue = "test"

        modePopup.addItems(withTitles: ["JSON", "Shell"])

        let run = button("Run", #selector(runQuery))
        run.keyEquivalent = "\r"
        run.keyEquivalentModifierMask = [.command]

        let cancel = button("Cancel", #selector(cancelQuery))
        let save = button("Save", #selector(saveWorksheet))
        let load = button("Load", #selector(loadWorksheet))
        let clear = button("Clear", #selector(clearOutput))

        view.addArrangedSubview(row([targetPopup, databaseField, modePopup, run, cancel, save, load, clear, status]))

        queryView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        queryView.string = "db.getCollectionNames()"
        queryView.isRichText = false
        queryView.isAutomaticQuoteSubstitutionEnabled = false
        queryView.isAutomaticDashSubstitutionEnabled = false
        outputView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        outputView.isEditable = false

        let queryScroll = scroll(queryView)
        let outputScroll = scroll(outputView)
        queryScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        outputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        view.addArrangedSubview(label("Worksheet"))
        view.addArrangedSubview(queryScroll)
        view.addArrangedSubview(label("Output"))
        view.addArrangedSubview(outputScroll)
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
        return label
    }

    private func scroll(_ textView: NSTextView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        return scroll
    }

    @objc private func addConnection() {
        let alert = NSAlert()
        alert.messageText = "Add MongoDB Connection"
        alert.addButton(withTitle: "Connect")
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
        let connection = Connection(name: name.stringValue, uri: uri.stringValue, database: db.stringValue)
        connections.append(connection)
        ConnectionStore.save(connections)
        table.reloadData()
        rebuildTargets(selecting: connection.id)
        refreshTree()
        status.stringValue = "Connected: \(connection.name)"
    }

    private func field(_ placeholder: String, _ value: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        return field
    }

    @objc private func disconnectConnection() {
        let row = table.selectedRow
        guard connections.indices.contains(row) else { return }
        let removed = connections.remove(at: row)
        ConnectionStore.delete(removed)
        ConnectionStore.save(connections)
        table.reloadData()
        rebuildTargets(selecting: connections.first?.id)
        refreshTree()
        status.stringValue = connections.isEmpty ? "Disconnected" : "Connected"
    }

    @objc private func refreshTree() {
        guard !connections.isEmpty else {
            treeRoots = []
            outline.reloadData()
            return
        }

        treeRoots = connections.map {
            TreeNode($0.name, connectionID: $0.id, children: [TreeNode("Loading...")])
        }
        outline.reloadData()
        for root in treeRoots {
            outline.expandItem(root)
        }

        for connection in connections {
            runner.listDatabases(uri: connection.uri) { [weak self] result in
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
                    root.children = [TreeNode(message.trimmingCharacters(in: .whitespacesAndNewlines))]
                }

                self.outline.reloadData()
                self.outline.expandItem(root)
                self.status.stringValue = "Database tree refreshed"
            }
        }
    }

    @objc private func targetChanged() {
        selectConnection(targetPopup.indexOfSelectedItem)
    }

    private func selectConnection(_ index: Int) {
        guard connections.indices.contains(index) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        databaseField.stringValue = connections[index].database
        status.stringValue = "Connected: \(connections[index].name)"
    }

    private func rebuildTargets(selecting selectedID: UUID?) {
        targetPopup.removeAllItems()
        for connection in connections {
            targetPopup.addItem(withTitle: connection.name)
        }
        if let id = selectedID, let index = connections.firstIndex(where: { $0.id == id }) {
            targetPopup.selectItem(at: index)
            selectConnection(index)
        } else if connections.isEmpty {
            targetPopup.addItem(withTitle: "No connection")
        }
    }

    @objc private func runQuery() {
        let index = targetPopup.indexOfSelectedItem
        guard connections.indices.contains(index) else {
            outputView.string = "Add a connection first."
            return
        }

        var connection = connections[index]
        connection.database = databaseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        connections[index] = connection
        ConnectionStore.save(connections)
        table.reloadData()

        status.stringValue = "Running..."
        let json = modePopup.titleOfSelectedItem == "JSON"
        runner.run(uri: connection.uri, database: connection.database, query: queryView.string, json: json) { [weak self] text in
            self?.outputView.string = text
            self?.status.stringValue = "Done"
        }
    }

    @objc private func cancelQuery() {
        runner.cancel()
        status.stringValue = "Cancelled"
    }

    @objc private func clearOutput() {
        outputView.string = ""
    }

    @objc private func saveWorksheet() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.javaScript]
        panel.nameFieldStringValue = "worksheet.mongo.js"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try queryView.string.write(to: url, atomically: true, encoding: .utf8)
            status.stringValue = "Saved"
        } catch {
            outputView.string = error.localizedDescription
        }
    }

    @objc private func loadWorksheet() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.javaScript, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            queryView.string = try String(contentsOf: url, encoding: .utf8)
            status.stringValue = "Loaded"
        } catch {
            outputView.string = error.localizedDescription
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
