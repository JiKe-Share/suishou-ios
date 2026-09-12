import Foundation
import Combine
import Security

struct Note: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var text: String
    var pinned = false
    var sortOrder = 0
    var createdAt = Date()
    var updatedAt = Date()
    var wire: [String: Any] {
        let f = ISO8601DateFormatter()
        return ["id": id, "title": title, "text": text, "pinned": pinned, "sort_order": sortOrder,
                "createdAt": f.string(from: createdAt), "updatedAt": f.string(from: updatedAt)]
    }
    static func date(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: value) { return d }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let d = iso.date(from: value) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss"] {
            f.dateFormat = format
            if let d = f.date(from: value) { return d }
        }
        return nil
    }
    static func decode(_ row: [String: Any]) throws -> Note {
        guard let id = row["id"] as? String, let title = row["title"] as? String,
              let text = row["text"] as? String, let c = row["createdAt"] as? String,
              let u = row["updatedAt"] as? String, let created = date(c), let updated = date(u) else {
            throw CloudError.message("服务器数据格式错误，本地数据已保留")
        }
        let pin = (row["pinned"] as? NSNumber)?.boolValue ?? (row["pinned"] as? String == "1")
        let order = (row["sort_order"] as? NSNumber)?.intValue ?? Int(row["sort_order"] as? String ?? "0") ?? 0
        return Note(id: id, title: title, text: text, pinned: pin, sortOrder: order, createdAt: created, updatedAt: updated)
    }
}
enum CloudError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let value): return value } }
}
struct Cache: Codable {
    var notes: [Note]
    var dirty: Set<String>
}
@MainActor final class NotesModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var status = ""
    @Published var busy = false
    @Published var loggedIn = false
    @Published var username = UserDefaults.standard.string(forKey: "username") ?? ""
    @Published var endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? "https://game.wxshares.com/ssc/index.php"
    private var token = ""
    private var dirty = Set<String>()
    private var loadFailed = false
    private let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("notes.json")
    var ordered: [Note] {
        notes.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.id < b.id
        }
    }
    init() {
        token = KeychainStore.read() ?? ""; loggedIn = !token.isEmpty
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let data = try Data(contentsOf: file)
            if let cache = try? JSONDecoder().decode(Cache.self, from: data) { notes = cache.notes; dirty = cache.dirty }
            else { notes = try JSONDecoder().decode([Note].self, from: data); dirty = Set(notes.map(\.id)) }
        } catch { loadFailed = true; status = "本地文件读取失败，已停止写入，请保留文件" }
    }
    private func persist() throws {
        if loadFailed { throw CloudError.message(status) }
        let data = try JSONEncoder().encode(Cache(notes: notes, dirty: dirty))
        if FileManager.default.fileExists(atPath: file.path) {
            try Data(contentsOf: file).write(to: file.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: file, options: .atomic)
    }
    private func commit(_ values: [Note]) -> Bool {
        guard !busy, !loadFailed else { return false }
        let old = notes, oldDirty = dirty
        for value in values {
            notes.removeAll { $0.id == value.id }; notes.append(value); dirty.insert(value.id)
        }
        do { try persist(); status = "已保存到本机"; Task { await synchronize() }; return true }
        catch { notes = old; dirty = oldDirty; status = error.localizedDescription; return false }
    }
    private var nextTime: Date {
        Date(timeIntervalSince1970: max(Date().timeIntervalSince1970, (notes.map { $0.updatedAt.timeIntervalSince1970 }.max() ?? 0) + 1))
    }
    func save(_ note: Note?, title: String, text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var value = note ?? Note(id: UUID().uuidString, title: "", text: "", sortOrder: (notes.map(\.sortOrder).min() ?? 0) - 1)
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(text.prefix(20)) : title
        value.text = text; value.updatedAt = nextTime
        return commit([value])
    }
    func move(_ note: Note, by offset: Int) {
        var group = ordered.filter { $0.pinned == note.pinned }
        guard let index = group.firstIndex(where: { $0.id == note.id }), group.indices.contains(index + offset) else { return }
        group.swapAt(index, index + offset); saveOrder(group)
    }
    func pin(_ note: Note) {
        var value = note; value.pinned.toggle()
        var group = ordered.filter { $0.id != note.id }; group.insert(value, at: 0); saveOrder(group)
    }
    private func saveOrder(_ group: [Note]) {
        let time = nextTime
        _ = commit(group.enumerated().map { index, note in
            var value = note; value.sortOrder = index; value.updatedAt = time; return value
        })
    }
    private func request(_ route: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + route), url.scheme == "https", url.host != nil else { throw CloudError.message("请输入 HTTPS 接口地址") }
        var req = URLRequest(url: url); req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw CloudError.message("服务器响应无效") }
        if http.statusCode == 401 { loggedIn = false; throw CloudError.message("请重新登录，凭证已过期或密码不正确") }
        guard (200..<300).contains(http.statusCode) else { throw CloudError.message("服务器错误 HTTP \(http.statusCode)，本地数据已保留") }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CloudError.message("服务器数据格式错误") }
        return result
    }
    func login(password: String) async {
        guard !busy else { return }; busy = true
        do {
            let result = try await request("/auth/login", body: ["username": username, "password": password])
            guard let value = result["token"] as? String, !value.isEmpty else { throw CloudError.message("未收到登录凭证") }
            try KeychainStore.save(value); token = value; loggedIn = true
            UserDefaults.standard.set(endpoint, forKey: "endpoint"); UserDefaults.standard.set(username, forKey: "username")
            status = "登录成功"
        } catch { status = error.localizedDescription }
        busy = false
        if loggedIn { await synchronize() }
    }
    func synchronize() async {
        guard !busy, loggedIn, !loadFailed else { return }; busy = true; defer { busy = false }
        do {
            let remote = try await request("/notes")
            let cloud = try decodeNotes(remote)
            let pending = notes.filter { dirty.contains($0.id) }
            for local in pending {
                if let other = cloud.first(where: { $0.id == local.id }), other.updatedAt > local.updatedAt {
                    throw CloudError.message("“\(local.title)”在另一端有较新版本，已保留本机修改，暂停上传")
                }
            }
            var synced = cloud
            if !pending.isEmpty { synced = try decodeNotes(try await request("/notes/sync", body: ["notes": pending.map(\.wire)])) }
            for item in pending {
                guard let found = synced.first(where: { $0.id == item.id }), found.title == item.title,
                      found.text == item.text, found.pinned == item.pinned, found.sortOrder == item.sortOrder else {
                    throw CloudError.message("云端核对未通过，本机修改已保留")
                }
            }
            let old = notes, oldDirty = dirty
            var merged = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
            for item in synced { merged[item.id] = item }
            notes = Array(merged.values); dirty.subtract(pending.map(\.id))
            do { try persist() } catch { notes = old; dirty = oldDirty; throw error }
            status = "已同步 \(notes.count) 条"
        } catch { status = error.localizedDescription }
    }
    private func decodeNotes(_ result: [String: Any]) throws -> [Note] {
        guard let rows = result["notes"] as? [[String: Any]] else { throw CloudError.message("云端列表格式错误") }
        let values = try rows.map(Note.decode)
        guard Set(values.map(\.id)).count == values.count else { throw CloudError.message("云端存在重复 ID") }
        return values
    }
}
enum KeychainStore {
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.suishou.cun.ios", kSecAttrAccount as String: "cloud-token"] }
    static func read() -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String) throws {
        let attrs = [kSecValueData as String: Data(token.utf8)]
        var code = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if code == errSecItemNotFound {
            var q = query; q.merge(attrs) { _, new in new }; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            code = SecItemAdd(q as CFDictionary, nil)
        }
        guard code == errSecSuccess else { throw CloudError.message("保存登录失败：\(code)") }
    }
}
