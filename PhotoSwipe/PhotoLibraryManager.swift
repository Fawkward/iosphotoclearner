import Foundation
import Photos
import UIKit

@MainActor
class PhotoLibraryManager: ObservableObject {
    // MARK: - Published state

    @Published var assets: [PHAsset] = []          // remaining photos to review (already filtered by reviewed-set)
    @Published var currentIndex: Int = 0
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false

    @Published var pendingDeletion: [PHAsset] = []        // marked but not yet deleted from library
    @Published var keptCount: Int = 0                     // kept in this session
    @Published var totalDeletedThisSession: Int = 0       // successfully removed from library
    @Published var totalReviewedAllTime: Int = 0          // across all sessions

    // MARK: - Persistent storage

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let reviewedIds = "PhotoSwipe.reviewedIdentifiers"   // kept OR confirmed-deleted
        static let pendingIds  = "PhotoSwipe.pendingDeleteIdentifiers"
        static let totalDeleted = "PhotoSwipe.totalDeletedAllTime"
    }

    /// IDs we've already shown to the user and they made a decision on.
    /// Includes both "kept" and "deleted" — so we skip them next launch.
    private var reviewedIdentifiers: Set<String> = []

    /// IDs marked for deletion but not yet committed.
    private var pendingIdentifiers: Set<String> = []

    // MARK: - Derived

    var currentAsset: PHAsset? {
        guard currentIndex < assets.count else { return nil }
        return assets[currentIndex]
    }

    var hasMorePhotos: Bool {
        currentIndex < assets.count
    }

    // MARK: - Init

    init() {
        loadPersistedState()
    }

    private func loadPersistedState() {
        if let arr = defaults.array(forKey: Keys.reviewedIds) as? [String] {
            reviewedIdentifiers = Set(arr)
        }
        if let arr = defaults.array(forKey: Keys.pendingIds) as? [String] {
            pendingIdentifiers = Set(arr)
        }
        totalReviewedAllTime = reviewedIdentifiers.count
    }

    private func savePersistedState() {
        defaults.set(Array(reviewedIdentifiers), forKey: Keys.reviewedIds)
        defaults.set(Array(pendingIdentifiers), forKey: Keys.pendingIds)
    }

    // MARK: - Authorization & load

    /// Called on app launch. If already authorized, just load. Otherwise request.
    func checkAuthorizationAndLoad() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = current
        switch current {
        case .authorized, .limited:
            await loadPhotos()
        case .notDetermined:
            await requestAuthorization()
        default:
            break
        }
    }

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.authorizationStatus = status
        if status == .authorized || status == .limited {
            await loadPhotos()
        }
    }

    /// Loads photos from the library, filtering out anything already reviewed.
    /// Restores pendingDeletion list if any was saved.
    func loadPhotos() async {
        isLoading = true
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var all: [PHAsset] = []
        var pendingAssets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            if self.pendingIdentifiers.contains(id) {
                // pending stays pending across launches
                pendingAssets.append(asset)
            } else if !self.reviewedIdentifiers.contains(id) {
                // not yet seen — to review
                all.append(asset)
            }
            // else: already reviewed in a past session, skip
        }

        // clean up stale pending IDs (photos that no longer exist in library)
        let livePendingIds = Set(pendingAssets.map { $0.localIdentifier })
        self.pendingIdentifiers = livePendingIds
        savePersistedState()

        self.assets = all
        self.pendingDeletion = pendingAssets
        self.currentIndex = 0
        self.keptCount = 0
        self.totalDeletedThisSession = 0
        self.totalReviewedAllTime = reviewedIdentifiers.count
        isLoading = false
    }

    /// Full reset — clear all history and start from the very first photo again.
    func resetAllProgress() async {
        reviewedIdentifiers = []
        pendingIdentifiers = []
        savePersistedState()
        await loadPhotos()
    }

    // MARK: - Image fetch

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

    // MARK: - Actions

    func keep() {
        guard let asset = currentAsset else { return }
        reviewedIdentifiers.insert(asset.localIdentifier)
        totalReviewedAllTime = reviewedIdentifiers.count
        keptCount += 1
        currentIndex += 1
        savePersistedState()
    }

    /// Mark current photo for deletion (does NOT delete from library yet).
    func markForDeletion() {
        guard let asset = currentAsset else { return }
        pendingIdentifiers.insert(asset.localIdentifier)
        pendingDeletion.append(asset)
        currentIndex += 1
        savePersistedState()
    }

    /// Undo last action.
    func undoLast() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        let asset = assets[currentIndex]
        let id = asset.localIdentifier
        if pendingIdentifiers.contains(id) {
            pendingIdentifiers.remove(id)
            pendingDeletion.removeAll { $0.localIdentifier == id }
        } else if reviewedIdentifiers.contains(id) {
            reviewedIdentifiers.remove(id)
            totalReviewedAllTime = reviewedIdentifiers.count
            if keptCount > 0 { keptCount -= 1 }
        }
        savePersistedState()
    }

    /// Commit all pending deletions to the photo library in one system prompt.
    func commitDeletions() async -> Bool {
        guard !pendingDeletion.isEmpty else { return false }
        let toDelete = pendingDeletion
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
            }
            // user confirmed → these IDs become "reviewed" (deleted branch) and leave pending
            let deletedIds = Set(toDelete.map { $0.localIdentifier })
            for id in deletedIds {
                pendingIdentifiers.remove(id)
                reviewedIdentifiers.insert(id)
            }
            totalDeletedThisSession += toDelete.count
            totalReviewedAllTime = reviewedIdentifiers.count

            let oldDeletedTotal = defaults.integer(forKey: Keys.totalDeleted)
            defaults.set(oldDeletedTotal + toDelete.count, forKey: Keys.totalDeleted)

            self.pendingDeletion = []
            // remove them from working list too
            let oldCurrentId = currentAsset?.localIdentifier
            self.assets.removeAll { deletedIds.contains($0.localIdentifier) }
            if let oldId = oldCurrentId,
               let newIdx = assets.firstIndex(where: { $0.localIdentifier == oldId }) {
                self.currentIndex = newIdx
            } else {
                self.currentIndex = min(self.currentIndex, self.assets.count)
            }
            savePersistedState()
            return true
        } catch {
            print("Batch delete cancelled or failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Empty the pending list without deleting from library (un-mark all).
    func clearPending() {
        for id in pendingIdentifiers {
            // these go back into the un-reviewed pool — user said "I changed my mind"
            _ = id
        }
        pendingIdentifiers = []
        pendingDeletion = []
        savePersistedState()
        // Reload so the un-marked photos reappear in the queue
        Task { await loadPhotos() }
    }
}
