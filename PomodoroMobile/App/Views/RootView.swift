import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        CanvasView()
        .tint(AppPalette.accent)
        .task { store.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in store.setActive(phase == .active) }
        .alert("温馨提示", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
