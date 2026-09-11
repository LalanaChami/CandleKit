import SwiftUI

@main
struct CandleKitDemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            MarketView()
                .tabItem { Label("Market", systemImage: "chart.bar.xaxis") }
            StylesView()
                .tabItem { Label("Styles", systemImage: "paintpalette") }
            AssetDetailView()
                .tabItem { Label("In a page", systemImage: "doc.richtext") }
            PerformanceView()
                .tabItem { Label("Performance", systemImage: "speedometer") }
        }
    }
}

#Preview {
    RootView()
}
