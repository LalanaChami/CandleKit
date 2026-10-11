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
    @Bindable private var router = DemoRouter.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            MarketView()
                .tabItem { Label("Market", systemImage: "chart.bar.xaxis") }
                .tag(0)
            StylesView()
                .tabItem { Label("Styles", systemImage: "paintpalette") }
                .tag(1)
            AssetDetailView()
                .tabItem { Label("In a page", systemImage: "doc.richtext") }
                .tag(2)
            PerformanceView()
                .tabItem { Label("Performance", systemImage: "speedometer") }
                .tag(3)
        }
    }
}

#Preview {
    RootView()
}
