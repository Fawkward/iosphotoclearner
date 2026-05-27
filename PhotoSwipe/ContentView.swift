import SwiftUI
import Photos
import AVKit

// MARK: - Swiper view (used for both photo and video tabs)

struct SwiperView: View {
    @ObservedObject var library: PhotoLibraryManager
    @State private var showingDeleteConfirm = false
    @State private var showingResetConfirm = false
    @State private var showingGrid = false

    var body: some View {
        Group {
            switch library.authorizationStatus {
            case .notDetermined:
                requestAccessView
            case .authorized, .limited:
                content
            case .denied, .restricted:
                deniedView
            @unknown default:
                deniedView
            }
        }
        .task {
            await library.checkAuthorizationAndLoad()
        }
        .confirmationDialog(
            "Начать сначала?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Да, сбросить прогресс", role: .destructive) {
                Task { await library.resetAllProgress() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Очистит историю просмотренных \(library.kind == .photo ? "фото" : "видео"). Сами файлы не пострадают.")
        }
    }

    // MARK: subviews

    private var requestAccessView: some View {
        VStack(spacing: 20) {
            Text("PhotoSwipe").font(.largeTitle).bold()
            Text("Нужен доступ к медиа-библиотеке")
            ProgressView()
        }
        .padding()
    }

    private var deniedView: some View {
        VStack(spacing: 20) {
            Text("Нет доступа").font(.title2).bold()
            Text("Разрешите доступ в Настройках → PhotoSwipe → Фото → Все фото")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Открыть настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if library.isLoading {
            ProgressView("Загрузка...")
        } else if !library.hasMoreAssets {
            finishedView
        } else {
            VStack(spacing: 12) {
                topBar
                if let asset = library.currentAsset {
                    Group {
                        if library.kind == .video {
                            VideoSwipeCard(asset: asset, library: library, key: asset.localIdentifier)
                        } else {
                            PhotoSwipeCard(asset: asset, library: library, key: asset.localIdentifier)
                        }
                    }
                    .id(asset.localIdentifier)
                }
                bottomBar
            }
            .padding()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                library.undoLast()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .foregroundColor(library.currentIndex > 0 ? .blue : .gray.opacity(0.4))
            }
            .disabled(library.currentIndex == 0)

            Button {
                showingGrid = true
            } label: {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }

            Spacer()

            Text("\(library.currentIndex + 1) / \(library.assets.count)")
                .font(.headline)
                .monospacedDigit()

            Spacer()

            Button {
                if !library.pendingDeletion.isEmpty {
                    showingDeleteConfirm = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text("\(library.pendingDeletion.count)")
                        .monospacedDigit()
                }
                .font(.title3.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(library.pendingDeletion.isEmpty ? Color.gray.opacity(0.4) : Color.red)
                )
            }
            .disabled(library.pendingDeletion.isEmpty)
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                if library.totalReviewedAllTime > 0 {
                    Text("Пройдено: \(library.totalReviewedAllTime)")
                }
                if library.pendingSizeBytes > 0 {
                    Text("• Освободишь: \(ByteFormatter.format(library.pendingSizeBytes))")
                        .foregroundColor(.red)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .offset(y: 18)
        }
        .padding(.bottom, (library.totalReviewedAllTime > 0 || library.pendingSizeBytes > 0) ? 18 : 0)
        .sheet(isPresented: $showingGrid) {
            GridPreviewView(library: library, onSelect: { idx in
                library.jumpTo(index: idx)
                showingGrid = false
            }, onClose: {
                showingGrid = false
            })
        }
        .confirmationDialog(
            "Удалить \(library.pendingDeletion.count) \(library.kind == .photo ? "фото" : "видео")?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить \(library.pendingDeletion.count)", role: .destructive) {
                Task { _ = await library.commitDeletions() }
            }
            Button("Очистить список", role: .destructive) {
                library.clearPending()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Файлы попадут в «Недавно удалённые». Освободится: \(ByteFormatter.format(library.pendingSizeBytes)).")
        }
    }

    private var bottomBar: some View {
        HStack {
            VStack(spacing: 4) {
                Image(systemName: "arrow.left")
                Text("В корзину").font(.caption)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("Оставлено")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(library.keptCount)")
                    .font(.title3.bold())
                    .foregroundColor(.green)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Image(systemName: "arrow.right")
                Text("Оставить").font(.caption)
            }
            .foregroundColor(.green)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }

    private var finishedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            if library.keptCount == 0 && library.totalDeletedThisSession == 0 && library.pendingDeletion.isEmpty {
                Text(library.kind == .photo ? "Все фото уже просмотрены" : "Все видео уже просмотрены")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Чтобы пройти заново — нажми кнопку ниже.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("Готово!").font(.largeTitle).bold()
                Text("Оставлено: \(library.keptCount)")
                    .font(.title3)
                    .foregroundColor(.green)
                if !library.pendingDeletion.isEmpty {
                    VStack(spacing: 4) {
                        Text("В корзине: \(library.pendingDeletion.count)")
                            .font(.title3)
                            .foregroundColor(.orange)
                        Text("Освободишь: \(ByteFormatter.format(library.pendingSizeBytes))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.red)
                    }
                    Button("Удалить \(library.pendingDeletion.count)") {
                        showingDeleteConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                if library.totalDeletedThisSession > 0 {
                    VStack(spacing: 2) {
                        Text("Удалено за сессию: \(library.totalDeletedThisSession)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if library.freedSizeThisSession > 0 {
                            Text("Освобождено: \(ByteFormatter.format(library.freedSizeThisSession))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            if library.totalReviewedAllTime > 0 {
                Text("Всего пройдено: \(library.totalReviewedAllTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            Button("Начать сначала") {
                showingResetConfirm = true
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .padding(.top)
        }
        .padding()
        .confirmationDialog(
            "Удалить \(library.pendingDeletion.count)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить \(library.pendingDeletion.count)", role: .destructive) {
                Task { _ = await library.commitDeletions() }
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}

// MARK: - Swipe gesture mixin (shared logic between photo and video cards)

struct SwipeGestureState {
    var offset: CGSize = .zero
    var isProcessing: Bool = false
}

// MARK: - Photo card

struct PhotoSwipeCard: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibraryManager
    let key: String

    @State private var image: UIImage?
    @State private var loadProgress: Double = 0
    @State private var loadFailed: Bool = false
    @State private var fileSize: Int64 = 0
    @State private var offset: CGSize = .zero
    @State private var isProcessing: Bool = false

    private let swipeThreshold: CGFloat = 120

    var body: some View {
        cardContent
            .offset(x: offset.width, y: 0)
            .rotationEffect(.degrees(Double(offset.width) / 20.0))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isProcessing { offset = value.translation }
                    }
                    .onEnded { value in
                        handleSwipeEnd(translation: value.translation)
                    }
            )
            .task(id: key) {
                await loadFullImage()
            }
    }

    private func loadFullImage() async {
        image = nil
        loadProgress = 0
        loadFailed = false

        // 1. show a fast cached thumbnail immediately (no network)
        let thumbSize = CGSize(width: 600, height: 600)
        if let thumb = await library.loadThumbnail(for: asset, targetSize: thumbSize) {
            image = thumb
        }

        // 2. compute file size in background
        Task.detached { [asset] in
            let size = PhotoLibraryManager.fileSize(of: asset)
            await MainActor.run { fileSize = size }
        }

        // 3. start full-quality load (may download from iCloud)
        let scale = UIScreen.main.scale
        let fullSize = CGSize(width: 1000 * scale, height: 1000 * scale)
        let result = await library.loadImage(
            for: asset,
            targetSize: fullSize,
            onProgress: { p in loadProgress = p }
        )
        if let result = result {
            image = result
            loadProgress = 1.0
        } else if image == nil {
            // no thumbnail and no full image — real failure
            loadFailed = true
        }
    }

    private var cardContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemGray6))

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(20)
            } else if loadFailed {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.icloud")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Не удалось загрузить")
                        .font(.headline)
                    Text("Возможно, нет интернета или фото удалено")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Повторить") {
                        Task { await loadFullImage() }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding()
            } else {
                VStack(spacing: 8) {
                    ProgressView(value: loadProgress)
                        .frame(width: 120)
                    if loadProgress > 0 && loadProgress < 1 {
                        Text("Загрузка из iCloud… \(Int(loadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // bottom info bar — date + size
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(AssetDateFormatter.format(asset.creationDate))
                        .lineLimit(1)
                    if fileSize > 0 {
                        Text("•")
                        Image(systemName: "internaldrive")
                        Text(ByteFormatter.format(fileSize))
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .padding(.bottom, 16)
            }

            // tint overlay
            RoundedRectangle(cornerRadius: 20)
                .fill(offset.width < 0
                      ? Color.red.opacity(min(Double(abs(offset.width)) / 300.0, 0.5))
                      : Color.green.opacity(min(Double(offset.width) / 300.0, 0.5)))
                .allowsHitTesting(false)

            if abs(offset.width) > 30 {
                Text(offset.width < 0 ? "В КОРЗИНУ" : "ОСТАВИТЬ")
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(offset.width < 0 ? Color.red : Color.green)
                    )
                    .rotationEffect(.degrees(offset.width < 0 ? -15 : 15))
                    .opacity(min(Double(abs(offset.width)) / Double(swipeThreshold), 1.0))
            }
        }
    }

    private func handleSwipeEnd(translation: CGSize) {
        guard !isProcessing else { return }
        if translation.width < -swipeThreshold {
            isProcessing = true
            withAnimation(.easeOut(duration: 0.25)) {
                offset = CGSize(width: -600, height: translation.height)
            }
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                library.markForDeletion()
            }
        } else if translation.width > swipeThreshold {
            isProcessing = true
            withAnimation(.easeOut(duration: 0.25)) {
                offset = CGSize(width: 600, height: translation.height)
            }
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                library.keep()
            }
        } else {
            withAnimation(.spring()) { offset = .zero }
        }
    }
}

// MARK: - Video card

struct VideoSwipeCard: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibraryManager
    let key: String

    @State private var player: AVPlayer?
    @State private var thumbnail: UIImage?
    @State private var fileSize: Int64 = 0
    @State private var offset: CGSize = .zero
    @State private var isProcessing: Bool = false

    private let swipeThreshold: CGFloat = 120

    var body: some View {
        cardContent
            .offset(x: offset.width, y: 0)
            .rotationEffect(.degrees(Double(offset.width) / 20.0))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isProcessing { offset = value.translation }
                    }
                    .onEnded { value in
                        handleSwipeEnd(translation: value.translation)
                    }
            )
            .task(id: key) {
                // fast cached thumbnail (no network wait)
                let scale = UIScreen.main.scale
                let size = CGSize(width: 800 * scale, height: 800 * scale)
                thumbnail = await library.loadThumbnail(for: asset, targetSize: size)
                // file size in background
                Task.detached { [asset] in
                    let s = PhotoLibraryManager.fileSize(of: asset)
                    await MainActor.run { fileSize = s }
                }
                await loadVideo()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }

    private var cardContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)

            // Background = thumbnail until video player ready
            if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(20)
                    .opacity(player == nil ? 1.0 : 0.0)
            }

            if let player = player {
                VideoPlayer(player: player)
                    .cornerRadius(20)
                    .allowsHitTesting(false) // so swipe works on top of video area
            } else {
                ProgressView()
            }

            // Top-right duration badge
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                        Text(DurationFormatter.format(asset.duration))
                            .monospacedDigit()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(12)
                }
                Spacer()
            }

            // Bottom date badge + size
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(AssetDateFormatter.format(asset.creationDate))
                        .lineLimit(1)
                    if fileSize > 0 {
                        Text("•")
                        Image(systemName: "internaldrive")
                        Text(ByteFormatter.format(fileSize))
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .padding(.bottom, 16)
            }

            // tint overlay
            RoundedRectangle(cornerRadius: 20)
                .fill(offset.width < 0
                      ? Color.red.opacity(min(Double(abs(offset.width)) / 300.0, 0.5))
                      : Color.green.opacity(min(Double(offset.width) / 300.0, 0.5)))
                .allowsHitTesting(false)

            if abs(offset.width) > 30 {
                Text(offset.width < 0 ? "В КОРЗИНУ" : "ОСТАВИТЬ")
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(offset.width < 0 ? Color.red : Color.green)
                    )
                    .rotationEffect(.degrees(offset.width < 0 ? -15 : 15))
                    .opacity(min(Double(abs(offset.width)) / Double(swipeThreshold), 1.0))
            }
        }
    }

    private func loadVideo() async {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        let item: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }

        guard let item = item else { return }
        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .none
        // loop the video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            p.seek(to: .zero)
            p.play()
        }
        self.player = p
        p.play()
    }

    private func handleSwipeEnd(translation: CGSize) {
        guard !isProcessing else { return }
        if translation.width < -swipeThreshold {
            isProcessing = true
            player?.pause()
            withAnimation(.easeOut(duration: 0.25)) {
                offset = CGSize(width: -600, height: translation.height)
            }
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                library.markForDeletion()
            }
        } else if translation.width > swipeThreshold {
            isProcessing = true
            player?.pause()
            withAnimation(.easeOut(duration: 0.25)) {
                offset = CGSize(width: 600, height: translation.height)
            }
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                library.keep()
            }
        } else {
            withAnimation(.spring()) { offset = .zero }
        }
    }
}

// MARK: - Grid preview (jump-to-start picker)

struct GridPreviewView: View {
    @ObservedObject var library: PhotoLibraryManager
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 4)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(library.assets.enumerated()), id: \.element.localIdentifier) { idx, asset in
                        GridThumb(asset: asset,
                                  library: library,
                                  index: idx,
                                  isCurrent: idx == library.currentIndex,
                                  isPending: library.pendingDeletion.contains(where: { $0.localIdentifier == asset.localIdentifier }))
                            .onTapGesture {
                                onSelect(idx)
                            }
                    }
                }
                .padding(4)
            }
            .navigationTitle("Выбери с чего начать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { onClose() }
                }
            }
        }
    }
}

struct GridThumb: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibraryManager
    let index: Int
    let isCurrent: Bool
    let isPending: Bool

    @State private var thumb: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Color(.systemGray5))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumb = thumb {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView()
                    }
                }
                .clipped()
                .overlay {
                    if isCurrent {
                        Rectangle()
                            .strokeBorder(Color.blue, lineWidth: 3)
                    }
                    if isPending {
                        Rectangle()
                            .fill(Color.red.opacity(0.4))
                    }
                }

            // duration badge for videos
            if asset.mediaType == .video {
                Text(DurationFormatter.format(asset.duration))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(4)
            }
            if isPending {
                Image(systemName: "trash.fill")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Circle().fill(Color.red))
                    .padding(4)
            }
        }
        .task {
            // load tiny thumb — cached locally, no iCloud wait
            thumb = await library.loadThumbnail(
                for: asset,
                targetSize: CGSize(width: 200, height: 200)
            )
        }
    }
}
