import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var library = PhotoLibraryManager()
    @State private var showingDeleteConfirm = false
    @State private var showingResetConfirm = false
    @State private var deletingInProgress = false

    var body: some View {
        Group {
            switch library.authorizationStatus {
            case .notDetermined:
                requestAccessView
            case .authorized, .limited:
                swipeView
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
            Text("Это очистит историю просмотренных фото. Сами фото не пострадают.")
        }
    }

    private var requestAccessView: some View {
        VStack(spacing: 20) {
            Text("PhotoSwipe").font(.largeTitle).bold()
            Text("Нужен доступ к фотографиям")
            ProgressView()
        }
        .padding()
    }

    private var deniedView: some View {
        VStack(spacing: 20) {
            Text("Нет доступа к фото").font(.title2).bold()
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
    private var swipeView: some View {
        if library.isLoading {
            ProgressView("Загрузка фото...")
        } else if !library.hasMorePhotos {
            finishedView
        } else {
            VStack(spacing: 12) {
                topBar
                if let asset = library.currentAsset {
                    SwipeCard(
                        asset: asset,
                        library: library,
                        key: asset.localIdentifier
                    )
                    .id(asset.localIdentifier)
                }
                bottomBar
            }
            .padding()
        }
    }

    private var topBar: some View {
        HStack {
            // Undo button
            Button {
                library.undoLast()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title)
                    .foregroundColor(library.currentIndex > 0 ? .blue : .gray.opacity(0.4))
            }
            .disabled(library.currentIndex == 0)

            Spacer()

            // Position counter
            Text("\(library.currentIndex + 1) / \(library.assets.count)")
                .font(.headline)
                .monospacedDigit()

            Spacer()

            // Trash bin counter — tap to commit deletions
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
            if library.totalReviewedAllTime > 0 {
                Text("Всего пройдено: \(library.totalReviewedAllTime)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .offset(y: 18)
            }
        }
        .padding(.bottom, library.totalReviewedAllTime > 0 ? 18 : 0)
        .confirmationDialog(
            "Удалить \(library.pendingDeletion.count) фото?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить \(library.pendingDeletion.count) фото", role: .destructive) {
                Task {
                    deletingInProgress = true
                    _ = await library.commitDeletions()
                    deletingInProgress = false
                }
            }
            Button("Очистить список", role: .destructive) {
                library.clearPending()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Фото попадут в «Недавно удалённые» и будут храниться 30 дней.")
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
                Text("Все фото уже просмотрены").font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Чтобы пройти галерею заново — нажми кнопку ниже.")
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
                    Text("В корзине: \(library.pendingDeletion.count)")
                        .font(.title3)
                        .foregroundColor(.orange)
                    Button("Удалить \(library.pendingDeletion.count) фото") {
                        showingDeleteConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                if library.totalDeletedThisSession > 0 {
                    Text("Удалено за сессию: \(library.totalDeletedThisSession)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            if library.totalReviewedAllTime > 0 {
                Text("Всего пройдено за всё время: \(library.totalReviewedAllTime)")
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
            "Удалить \(library.pendingDeletion.count) фото?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить \(library.pendingDeletion.count) фото", role: .destructive) {
                Task { _ = await library.commitDeletions() }
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}

struct SwipeCard: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibraryManager
    let key: String

    @State private var image: UIImage?
    @State private var offset: CGSize = .zero
    @State private var isProcessing: Bool = false

    private let swipeThreshold: CGFloat = 120

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemGray6))

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(20)
            } else {
                ProgressView()
            }

            // tint overlay
            RoundedRectangle(cornerRadius: 20)
                .fill(offset.width < 0
                      ? Color.red.opacity(min(Double(abs(offset.width)) / 300.0, 0.5))
                      : Color.green.opacity(min(Double(offset.width) / 300.0, 0.5)))
                .allowsHitTesting(false)

            // big indicator label
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
            let scale = UIScreen.main.scale
            let size = CGSize(width: 1000 * scale, height: 1000 * scale)
            image = await library.loadImage(for: asset, targetSize: size)
        }
    }

    private func handleSwipeEnd(translation: CGSize) {
        guard !isProcessing else { return }

        if translation.width < -swipeThreshold {
            // mark for deletion (instant, no system prompt)
            isProcessing = true
            withAnimation(.easeOut(duration: 0.25)) {
                offset = CGSize(width: -600, height: translation.height)
            }
            // small delay so user sees the card fly off
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                library.markForDeletion()
            }
        } else if translation.width > swipeThreshold {
            // keep
            isProcessing = true
            withAnimation(.easeOut(duration: 0.25)) {
                offset = CGSize(width: 600, height: translation.height)
            }
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                library.keep()
            }
        } else {
            // snap back
            withAnimation(.spring()) { offset = .zero }
        }
    }
}
