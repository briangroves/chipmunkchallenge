import Combine
import StoreKit
import SwiftUI

/// The Pro upgrade: one non-consumable In-App Purchase that unlocks the table backgrounds, auto-finish, the nest
/// queue, the speed settings, the daily gift, Undo and fast-forward.
///
/// The purchase belongs to the player's Apple Account, not to this device: StoreKit 2 keeps the signed transaction,
/// so a reinstall or a new iPhone signed in to the same account is Pro again on launch (and Restore Purchases asks the
/// App Store directly). A refund takes Pro away again.
@MainActor
final class ProStore: ObservableObject {
    /// Must match the product created in App Store Connect (Features → In-App Purchases, type Non-Consumable).
    static let productID = "com.groveseng.chipmunkchallenge.pro"

    @Published private(set) var isPro: Bool
    @Published private(set) var product: Product?
    @Published private(set) var phase: Phase = .idle

    enum Phase: Equatable {
        case idle
        case loading
        case buying
        /// Ask to Buy: a parent has to approve it. The purchase arrives later through `Transaction.updates`.
        case pending
        case restoring
        case failed(String)
    }

    private static let cacheKey = "native.pro"
    private var updates: Task<Void, Never>?

    init() {
        // The last known answer, so a Pro player never sees the locks flash on while StoreKit is checked.
        isPro = UserDefaults.standard.bool(forKey: Self.cacheKey)
        #if DEBUG
        // `-pro YES` / `-pro NO` force either version for testing without a purchase.
        if UserDefaults.standard.object(forKey: "pro") != nil {
            isPro = UserDefaults.standard.bool(forKey: "pro")
            return
        }
        #endif
        updates = Task { [weak self] in
            // Purchases made elsewhere (another device, Ask to Buy approved later, a refund) arrive here.
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await refresh()
            await loadProduct()
        }
    }

    deinit { updates?.cancel() }

    /// The product's price as the App Store shows it in the player's country ("$4.99"), once loaded.
    var price: String? { product?.displayPrice }

    func loadProduct() async {
        guard product == nil else { return }
        if phase == .idle { phase = .loading }
        do {
            product = try await Product.products(for: [Self.productID]).first
            if phase == .loading { phase = product == nil ? .failed("The store isn't available right now.") : .idle }
        } catch {
            if phase == .loading { phase = .failed("Couldn't reach the App Store. Check your connection.") }
        }
    }

    func buy() async {
        if product == nil { await loadProduct() }
        guard let product else { return }
        phase = .buying
        do {
            switch try await product.purchase() {
            case .success(let result):
                await handle(result)
                phase = .idle
            case .pending:
                phase = .pending
            case .userCancelled:
                phase = .idle
            @unknown default:
                phase = .idle
            }
        } catch {
            phase = .failed("The purchase didn't go through. You weren't charged.")
        }
    }

    /// Restore Purchases: syncs with the App Store (it may ask the player to sign in), then rechecks.
    func restore() async {
        phase = .restoring
        do {
            try await AppStore.sync()
            await refresh()
            phase = isPro ? .idle : .failed("No Pro purchase was found for this Apple Account.")
        } catch {
            phase = .failed("Couldn't reach the App Store. Check your connection.")
        }
    }

    func clearError() {
        if case .failed = phase { phase = .idle }
    }

    /// Reads the current entitlements (the signed transactions StoreKit keeps for this Apple Account).
    func refresh() async {
        var owned = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil {
                owned = true
            }
        }
        set(owned)
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        // Only transactions signed by the App Store count.
        guard case .verified(let t) = result else { return }
        if t.productID == Self.productID {
            if t.revocationDate == nil {
                set(true)
                if phase == .pending { phase = .idle }
            } else {
                await refresh()
            }
        }
        await t.finish()
    }

    private func set(_ owned: Bool) {
        isPro = owned
        UserDefaults.standard.set(owned, forKey: Self.cacheKey)
    }
}

/// The Pro features, in the order the unlock screen lists them.
enum ProFeature: String, CaseIterable, Identifiable {
    case backgrounds, autoFinish, queue, speed, dailyGift, undo, fastForward

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backgrounds: return "Table backgrounds"
        case .autoFinish: return "Auto-finish last column"
        case .queue: return "Queue nests"
        case .speed: return "Speed control"
        case .dailyGift: return "Daily gift"
        case .undo: return "Undo"
        case .fastForward: return "Fast-forward"
        }
    }

    var detail: String {
        switch self {
        case .backgrounds: return "Linen, felt, sky, candy and night tables."
        case .autoFinish: return "The last column loads itself."
        case .queue: return "Line up nests while the slots are full."
        case .speed: return "Set your own normal and fast speeds."
        case .dailyGift: return "A free mystery box every day."
        case .undo: return "Take back your last tap."
        case .fastForward: return "Speed up any board."
        }
    }

    var symbol: String {
        switch self {
        case .backgrounds: return "paintpalette.fill"
        case .autoFinish: return "wand.and.stars"
        case .queue: return "list.number"
        case .speed: return "slider.horizontal.3"
        case .dailyGift: return "gift.fill"
        case .undo: return "arrow.uturn.backward"
        case .fastForward: return "forward.fill"
        }
    }
}

// MARK: - Locked controls

/// A Pro control in the free version: greyed out with a small gold lock, and a tap anywhere on it opens the unlock
/// screen instead of using it.
struct ProLock: ViewModifier {
    let locked: Bool
    let name: String
    let unlock: () -> Void
    var badgeOffset = CGSize(width: 5, height: -5)
    /// How much color is left: none for controls; the table swatches keep some, so players see what they'd get.
    var saturation: Double = 0

    func body(content: Content) -> some View {
        if locked {
            content
                .saturation(saturation)
                .opacity(saturation > 0 ? 0.7 : 0.45)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .overlay(alignment: .topTrailing) {
                    LockBadge().offset(badgeOffset)
                }
                .overlay {
                    Button(action: unlock) { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(name), locked. Unlock with Pro.")
                }
        } else {
            content
        }
    }
}

extension View {
    func proLock(_ locked: Bool, _ name: String, offset: CGSize = CGSize(width: 5, height: -5), saturation: Double = 0,
                 unlock: @escaping () -> Void) -> some View {
        modifier(ProLock(locked: locked, name: name, unlock: unlock, badgeOffset: offset, saturation: saturation))
    }
}

/// The lock on a Pro control: a gold coin with a dark padlock.
struct LockBadge: View {
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size * 0.52, weight: .heavy))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.gold))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Unlock screen

/// The unlock screen: what Pro adds, the one-time price, Buy and Restore.
struct ProSplash: View {
    @ObservedObject var model: GameModel
    @ObservedObject var store: ProStore
    /// The locked control that was tapped (its row is highlighted), if any.
    let feature: ProFeature?

    var body: some View {
        ZStack {
            Color(red: 20 / 255, green: 28 / 255, blue: 16 / 255, opacity: 0.6)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button { close() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Theme.button))
                    }
                    .buttonStyle(Pressable())
                    .accessibilityLabel("Close")
                }
                .padding(.bottom, -30)
                Text("🐿️").font(.system(size: 44))
                VStack(spacing: 2) {
                    Text("Chipmunk Pro")
                        .font(Theme.display(30))
                        .foregroundStyle(Theme.ink)
                    Text("Unlock everything, one time. No subscription.")
                        .font(Theme.body(14, 700))
                        .foregroundStyle(Color(hex: 0x4A5841))
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 6) {
                    ForEach(ProFeature.allCases) { f in
                        row(f)
                    }
                }
                buyButton
                status
                HStack(spacing: 18) {
                    Button("Restore Purchases") { Task { await store.restore() } }
                    Button("Not now") { close() }
                }
                .font(Theme.body(13, 800))
                .foregroundStyle(Color(hex: 0x4A5841))
                .disabled(busy)
                Text("A one-time purchase tied to your Apple Account. It unlocks Pro on every device signed in to that account, and Restore Purchases brings it back after a reinstall.")
                    .font(Theme.body(11, 500))
                    .foregroundStyle(Color(hex: 0x7A8672))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: 0xFFFDF5))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 12))
            .padding(16)
        }
        .task { await store.loadProduct() }
        .onChange(of: store.isPro) { _, pro in
            if pro {
                model.buzzSuccess()
                close()
            }
        }
    }

    private var busy: Bool { store.phase == .buying || store.phase == .restoring }

    private func close() {
        store.clearError()
        model.closePaywall()
    }

    private func row(_ f: ProFeature) -> some View {
        let hot = f == feature
        return HStack(spacing: 10) {
            Image(systemName: f.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(hot ? Theme.gold : Theme.button))
            VStack(alignment: .leading, spacing: 0) {
                Text(f.title).font(Theme.body(14, 800)).foregroundStyle(Theme.ink)
                Text(f.detail).font(Theme.body(11.5, 500)).foregroundStyle(Color(hex: 0x5A6851))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 12).fill(hot ? Color(hex: 0xFFF3C4) : .clear))
        .accessibilityElement(children: .combine)
    }

    private var buyButton: some View {
        Button { Task { await store.buy() } } label: {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else if let price = store.price {
                    Text("Unlock Pro · \(price)")
                } else {
                    Text("Unlock Pro")
                }
            }
            .font(Theme.body(17, 800))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x2E7D32))
                .shadow(color: Color(hex: 0x1B5E20), radius: 0, y: 4))
        }
        .buttonStyle(Pressable())
        .disabled(busy || store.product == nil || store.phase == .pending)
        .opacity(store.product == nil && !busy ? 0.6 : 1)
    }

    @ViewBuilder private var status: some View {
        switch store.phase {
        case .pending:
            Text("Waiting for approval. Pro unlocks as soon as it's approved.")
                .font(Theme.body(12.5, 700)).foregroundStyle(Color(hex: 0x8A6500))
                .multilineTextAlignment(.center)
        case .failed(let why):
            Text(why)
                .font(Theme.body(12.5, 700)).foregroundStyle(Color(hex: 0xC62828))
                .multilineTextAlignment(.center)
        case .loading:
            Text("Loading the price…").font(Theme.body(12.5, 700)).foregroundStyle(Color(hex: 0x7A8672))
        default:
            EmptyView()
        }
    }
}
