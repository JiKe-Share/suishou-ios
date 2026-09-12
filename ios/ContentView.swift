import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: NotesModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var editing: Note?
    @State private var adding = false
    @State private var settings = false
    @State private var copied = false
    var body: some View {
        NavigationStack {
            List {
                if !model.status.isEmpty { Text(model.status).font(.caption).foregroundStyle(.secondary) }
                ForEach(model.ordered.filter { search.isEmpty || ($0.title + $0.text).localizedCaseInsensitiveContains(search) }) { note in
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            UIPasteboard.general.string = note.text; copied = true
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    if note.pinned { Image(systemName: "pin.fill").foregroundStyle(.mint) }
                                    Text(note.title).font(.headline).foregroundStyle(.primary)
                                }
                                Text(note.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        HStack(spacing: 22) {
                            Text(note.updatedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Button { model.move(note, by: -1) } label: { Image(systemName: "arrow.up") }.accessibilityLabel("上移")
                            Button { model.move(note, by: 1) } label: { Image(systemName: "arrow.down") }.accessibilityLabel("下移")
                            Button { model.pin(note) } label: { Image(systemName: note.pinned ? "pin.slash" : "pin") }.accessibilityLabel(note.pinned ? "取消置顶" : "置顶")
                            Button { editing = note } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("编辑")
                        }.buttonStyle(.borderless).disabled(model.busy)
                    }.padding(.vertical, 6)
                }
            }
            .searchable(text: $search, prompt: "搜索标题或内容")
            .navigationTitle("随手存")
            .refreshable { await model.synchronize() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("设置") }
                ToolbarItem(placement: .topBarTrailing) { Button { Task { await model.synchronize() } } label: { Image(systemName: "arrow.triangle.2.circlepath") }.disabled(model.busy || !model.loggedIn).accessibilityLabel("同步") }
                ToolbarItem(placement: .bottomBar) { Button { adding = true } label: { Label("存一条文本", systemImage: "plus") }.disabled(model.busy) }
            }
            .sheet(isPresented: $adding) { EditorView(note: nil) }
            .sheet(item: $editing) { EditorView(note: $0) }
            .sheet(isPresented: $settings) { SettingsView() }
            .alert("已复制", isPresented: $copied) { Button("好", role: .cancel) {} }
            .task { await model.synchronize() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.synchronize() } } }
        }.tint(.teal)
    }
}
struct SettingsView: View {
    @EnvironmentObject private var model: NotesModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("云端账号") {
                    TextField("API 地址", text: $model.endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.loggedIn)
                    TextField("用户名", text: $model.username).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.loggedIn)
                    if !model.loggedIn { SecureField("密码", text: $password) }
                    Button(model.loggedIn ? "立即同步" : "登录并同步") {
                        Task {
                            if model.loggedIn { await model.synchronize() }
                            else { await model.login(password: password); if model.loggedIn { password = "" } }
                        }
                    }.disabled(model.busy)
                    Text(model.status).font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("设置").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
struct EditorView: View {
    @EnvironmentObject private var model: NotesModel
    @Environment(\.dismiss) private var dismiss
    let note: Note?
    @State private var title = ""
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("备注标题（可选）", text: $title)
                TextEditor(text: $text).frame(minHeight: 260)
                Text("\(text.count) 字").font(.caption).foregroundStyle(.secondary)
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }.navigationTitle(note == nil ? "新增文本" : "编辑文本")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { if model.save(note, title: title, text: text) { dismiss() } }.disabled(model.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.onAppear { title = note?.title ?? ""; text = note?.text ?? "" }
        }.interactiveDismissDisabled()
    }
}
