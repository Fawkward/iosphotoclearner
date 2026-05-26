import Foundation
import Photos
import UIKit

@MainActor
class PhotoLibraryManager: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var currentIndex: Int = 0
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false

    // Accumulated state
    @Published var pendingDeletion: [PHAsset] = []   // photos marked for deletion
    @Published var keptCount: Int = 0
    @Published var totalDeletedThisSession: Int = 0  // successfully removed from library

    var currentAsset: PHAsset? {
        guard currentIndex < assets.count else { return nil }
        return assets[currentIndex]
    }

    var hasMorePhotos: Bool {
        currentIndex < assets.count
    }

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.authorizationStatus = status
        if status == .authorized || status == .limited {
            await loadPhotos()
        }
    }

    func loadPhotos() async {
        isLoading = true
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var loaded: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            loaded.append(asset)
        }
        self.assets = loaded
        self.currentIndex = 0
        self.keptCount = 0
        self.pendingDeletion = []
        self.totalDeletedThisSession = 0
        isLoading = false
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func keep() {
        guard hasMorePhotos else { return }
        keptCount += 1
        currentIndex += 1
    }

    /// Just marks the current photo for deletion — does NOT delete from library yet.
    func markForDeletion() {
        guard let asset = currentAsset else { return }
        pendingDeletion.append(asset)
        currentIndex += 1
    }

    /// Undo last action — removes last marked photo from pending list and goes back one step.
    /// Also handles undo for "keep" by just going back one step.
    func undoLast() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        // figure out whether the last action was a delete or a keep
        if let last = pendingDeletion.last,
           last.localIdentifier == assets[currentIndex].localIdentifier {
            pendingDeletion.removeLast()
        } else {
            // it was a keep
            if keptCount > 0 { keptCount -= 1 }
        }
    }

    /// Actually delete all pending photos in one system prompt.
    /// Returns true if user confirmed and photos were removed.
    func commitDeletions() async -> Bool {
        guard !pendingDeletion.isEmpty else { return false }
        let toDelete = pendingDeletion
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
            }
            self.totalDeletedThisSession += toDelete.count
            self.pendingDeletion = []
            // Remove the deleted assets from our working list too, so they don't reappear
            let deletedIds = Set(toDelete.map { $0.localIdentifier })
            let oldCurrentId = currentAsset?.localIdentifier
            self.assets.removeAll { deletedIds.contains($0.localIdentifier) }
            // restore current position relative to non-deleted assets
            if let oldId = oldCurrentId,
               let newIdx = assets.firstIndex(where: { $0.localIdentifier == oldId }) {
                self.currentIndex = newIdx
            } else {
                self.currentIndex = min(self.currentIndex, self.assets.count)
            }
            return true
        } catch {
            // User cancelled the system confirmation dialog — keep the pending list intact
            print("Batch delete cancelled or failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Clear the pending list without deleting anything (user changed their mind).
    func clearPending() {
        pendingDeletion = []
    }
}
