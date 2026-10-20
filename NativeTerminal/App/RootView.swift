import AppKit
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(TerminalController.self) private var controller
    @Query(sort: \TerminalSession.lastActivity, order: .reverse) private var sessions: [TerminalSession]
    @State private var searchText = ""
    @State private var searchSelection = 0
    @State private var searchOpenRequest = 0
    @State private var editingRecipe: SavedRecipe?
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    #endif

    private static var isAutomated: Bool {
        #if DEBUG
        DebugAutomation.environment["NATIVETERM_SCRIPT"] != nil
            || DebugAutomation.environment["NATIVETERM_SKIP_WELCOME"] != nil
        #else
        false
        #endif
    }

    var body: some View {
        @Bindable var controller = controller
        let selectedID = controller.selectedSessionID
        let selected = sessions.first { $0.id == selectedID }

        NavigationSplitView {
            SessionListView(sessions: sessions, searchText: $searchText, searchSelection: $searchSelection) {
                searchOpenRequest += 1
            }
                .navigationSplitViewColumnWidth(min: 240, ideal: 318, max: 380)
        } detail: {
            if !searchText.isEmpty {
                SearchResultsView(query: searchText, sessions: sessions, selection: $searchSelection,
                                  openRequest: searchOpenRequest) {
                    searchText = ""
                }
            } else if controller.selectedSessionIDs.count > 1 {
                MultipleSessionsView(sessions: sessions.filter { controller.selectedSessionIDs.contains($0.id) })
            } else if let selected {
                ChatView(session: selected)
                    .id(selected.id)
            } else {
                ContentUnavailableView(
                    "Sin sesión",
                    systemImage: "apple.terminal",
                    description: Text("Crea una sesión nueva para empezar.")
                )
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        // ⌘K floats over the whole window, like Spotlight.
        .overlay(alignment: .top) {
            if controller.isShowingRecipes, let selected {
                ZStack(alignment: .top) {
                    // A click anywhere else closes it.
                    Color.clear
                        .contentShape(.rect)
                        .ignoresSafeArea()
                        .onTapGesture { controller.isShowingRecipes = false }
                    RecipesView(
                        directory: controller.shells[selected.id]?.directory ?? selected.directory,
                        onRun: { controller.submit($0, in: selected) },
                        onInsert: { controller.draftRequest = $0 },
                        onEdit: { editingRecipe = $0 },
                        onClose: { controller.isShowingRecipes = false }
                    )
                    .padding(.top, 64)
                    .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.smooth(duration: 0.18), value: controller.isShowingRecipes)
        .sheet(item: $editingRecipe) { recipe in
            SavedRecipeEditor(editing: recipe)
        }

        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.markSelectedAsRead()
        }
        .sheet(isPresented: $controller.isShowingWelcome) {
            WelcomeView()
        }
        .task {
            if !UserDefaults.standard.bool(forKey: AppSettings.hasSeenWelcomeKey), !Self.isAutomated {
                controller.isShowingWelcome = true
            }
        }
        #if DEBUG
        .task { DebugAutomation.start(controller: controller) }
        .onDebugAction("#search") { searchText = $0 }
        .onDebugAction("#settings") { _ in openSettings() }
        .onDebugAction("#tools") { _ in openWindow(id: "tools") }
        #endif
    }
}
