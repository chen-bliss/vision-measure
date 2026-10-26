import SwiftUI

@main struct VisionMeasureApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
            #if os(macOS)
                .frame(minWidth: 780, minHeight: 720)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1040, height: 900)
        #endif
    }
}
