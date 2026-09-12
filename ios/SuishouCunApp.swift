import SwiftUI

@main
struct SuishouCunApp: App {
    @StateObject private var model = NotesModel()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model) }
    }
}
