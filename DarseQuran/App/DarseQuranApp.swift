import SwiftUI

@main
struct DarseQuranApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Scheme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image("Logo").resizable().frame(width: 96, height: 96).clipShape(Circle())
                    Text("Darse Quran Academy").textStyle(Typo.headlineMedium).foregroundStyle(Scheme.onBackground)
                    Text("Assalamu alaikum").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurfaceVariant)
                    Text("بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ").textStyle(Typo.arabic).foregroundStyle(Brand.gold)
                }
            }
        }
    }
}
