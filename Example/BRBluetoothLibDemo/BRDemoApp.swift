import SwiftUI

@main
struct BRDemoApp: App {
    @StateObject private var viewModel = BRDemoViewModel()

    var body: some Scene {
        WindowGroup {
            BRDemoContentView(viewModel: viewModel)
        }
    }
}
