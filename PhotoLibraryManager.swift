import Foundation
import Photos
import UIKit

enum MediaKind: String, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }

    var phMediaType: PHAssetMediaType {
        switch self {
        case .photo: return .image
        case .video: return .video
        }
    }

    var displayName: String {
        switch self {
        case .photo: return "Фото"
        case .video: return "Видео"
        }
    }

    var iconName: String {
        switch self {
        case .photo: return "photo.stack"
        case .video: return "video.fill"
        }
    }

    /// Suffix for UserDefaults keys so each kind has its own state
    var storageSuffix: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        }
    }
}

@MainActor
class PhotoLibraryManager: ObservableObject {
    let kind: MediaKind

    // MARK: - Published state

    @Published var assets: [PHAsset] = []
    @Published var currentIndex: Int = 0
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false

    @Published var pendingDeletion: [PHAsset] = []
    @Published var keptCount: Int = 0
    @Published var totalDeletedThisSession: Int = 0
    @Published var totalReviewedAllTime: Int = 0

    // MARK: - Persistent storage (per-kind)

    private let defaults = UserDefaults.standard
    private var reviewedKey: String { "PhotoSwipe.reviewedIdentifiers.\(kind.storageSuffix)" }
    private var pendingKey:  String { "PhotoSwipe.pendingDeleteIdentifiers.\(kind.storageSuffix)" }
    private var deletedTotalKey: String { "PhotoSwipe.totalDeletedAllTime.\(kind.storageSuffix)" }

    private var reviewedIdentifiers: Set<String> = []
    private var pendingIdentifiers: Set<String> = []

    var currentAsset: PHAsset? {
        guard currentIndex < assets.count else { return nil }
        return assets[currentIndex]
    }

    var hasMoreAssets: Bool {
        currentIndex < assets.count
    }

    // MARK: - Init

    init(kind: MediaKind) {
        self.kind = kind
        loadPersistedState()
    }

    private func loadPersistedState() {
        if let arr = defaults.array(forKey: reviewedKey) as? [String] {
            reviewedIdentifiers = Set(arr)
        }
        if let arr = defaults.array(forKey: pendingKey) as? [String] {
            pendingIdentifiers = Set(arr)
        }
        totalReviewedAllTime = reviewedIdentifiers.count
    }

    private func savePersistedState() {
        defaults.set(Array(reviewedIdentifiers), forKey: reviewedKey)
        defaults.set(Array(pendingIdentifiers), forKey: pendingKey)
    }

    // MARK: - Authorization & load

    func checkAuthorizationAndLoad() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = current
        switch current {
        case .authorized, .limited:
            await loadAssets()
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
            await loadAssets()
        }
    }

    func loadAssets() async {
        isLoading = true
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: kind.phMediaType, options: fetchOptions)

        var fresh: [PHAsset] = []
        var pendingAssets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            if self.pendingIdentifiers.contains(id) {
                pendingAssets.append(asset)
            } else if !self.reviewedIdentifiers.contains(id) {
                fresh.append(asset)
            }
        }

        let livePendingIds = Set(pendingAssets.map { $0.localIdentifier })
        self.pendingIdentifiers = livePendingIds
        savePersistedState()

        self.assets = fresh
        self.pendingDeletion = pendingAssets
        self.currentIndex = 0
        self.keptCount = 0
        self.totalDeletedThisSession = 0
        self.totalReviewedAllTime = reviewedIdentifiers.count
        isLoading = false
    }

    func resetAllProgress() async {
        reviewedIdentifiers = []
        pendingIdentifiers = []
        savePersistedState()
        await loadAssets()
    }

    // MARK: - Image fetch (for photos AND video thumbnails)

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

    func markForDeletion() {
        guard let asset = currentAsset else { return }
        pendingIdentifiers.insert(asset.localIdentifier)
        pendingDeletion.append(asset)
        currentIndex += 1
        savePersistedState()
    }

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

    func commitDeletions() async -> Bool {
        guard !pendingDeletion.isEmpty else { return false }
        let toDelete = pendingDeletion
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
            }
            let deletedIds = Set(toDelete.map { $0.localIdentifier })
            for id in deletedIds {
                pendingIdentifiers.remove(id)
                reviewedIdentifiers.insert(id)
            }
            totalDeletedThisSession += toDelete.count
            totalReviewedAllTime = reviewedIdentifiers.count

            let oldTotal = defaults.integer(forKey: deletedTotalKey)
            defaults.set(oldTotal + toDelete.count, forKey: deletedTotalKey)

            self.pendingDeletion = []
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

    func clearPending() {
        pendingIdentifiers = []
        pendingDeletion = []
        savePersistedState()
        Task { await loadAssets() }
    }
}

// MARK: - Date formatting helper

enum AssetDateFormatter {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    static func format(_ date: Date?) -> String {
        guard let date = date else { return "Дата неизвестна" }
        return formatter.string(from: date)
    }
}

// MARK: - Duration formatter for videos

enum DurationFormatter {
    static func format(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
