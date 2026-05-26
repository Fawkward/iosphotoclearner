import SwiftUI

@main
struct PhotoSwipeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var selectedTab: MediaKind = .photo

    // Each tab has its own manager with its own state
    @StateObject private var photoLibrary = PhotoLibraryManager(kind: .photo)
    @StateObject private var videoLibrary = PhotoLibraryManager(kind: .video)

    var body: some View {
        TabView(selection: $selectedTab) {
            SwiperView(library: photoLibrary)
                .tabItem {
                    Label(MediaKind.photo.displayName, systemImage: MediaKind.photo.iconName)
                }
                .tag(MediaKind.photo)

            SwiperView(library: videoLibrary)
                .tabItem {
                    Label(MediaKind.video.displayName, systemImage: MediaKind.video.iconName)
                }
                .tag(MediaKind.video)
        }
    }
}
