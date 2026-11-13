import ChipmunkEngine
import Foundation
import UIKit

/// What the slots and lanes show right now. Published only when it changes, so SwiftUI redraws them only then.
struct SideState: Equatable {
    struct SlotItem: Equatable {
        var c: Int
        var r: Int
        var key: Bool
        var magic: Bool
    }

    struct Lane: Equatable, Identifiable {
        var id: Int
        /// Front nest first, then up to three behind it (the fourth is the half-hidden preview).
        var nests: [NestSpec]
        /// Each shown nest's position in its lane (the lane's own numbering, which the queue uses).
        var at: [Int]
    }

    var slots: [SlotItem?] = []
    var lockedAt: Int?
    /// Slot columns the lanes line up with (the board's base slot count).
    var columns = 5
    var lanes: [Lane] = []
}

/// One board in play: loads (or builds) the board, runs the timed simulation, and takes the player's taps.
/// BoardView drives the clock every frame; SwiftUI shows the published state.
@MainActor
final class GameModel: ObservableObject {
    enum Status: Equatable {
        case building
        case playing
        case won
        case stuck
        case failed(String)
    }

    /// What kind of board is up: the next Level Play level, a Coin Mining board, or today's daily puzzle.
    enum Mode: Equatable { case level, mining, daily }

    @Published private(set) var status: Status = .building
    @Published private(set) var mode: Mode = .level
    /// The Level Play level being played, or the next one to play (saved).
    @Published private(set) var boardIndex: Int
    @Published private(set) var title = ""
    @Published private(set) var subtitle = ""
    /// The splash's small line above the title: Coin Mining or Daily puzzle (nothing for Level Play).
    @Published private(set) var modeLabel = ""
    @Published var fast = false
    /// Coin Mining boards cleared (the next board is this round).
    @Published private(set) var paraRound: Int
    /// The daily puzzle's record (JS `daily`): the last day cleared, the streak, the best streak and days cleared.
    struct Daily: Codable, Equatable {
        var last = -1
        var streak = 0
        var best = 0
        var count = 0
    }
    @Published private(set) var daily: Daily
    /// Nests lined up to load next while every slot is full (JS preQ), in the order they were tapped.
    struct Queued: Equatable {
        let l: Int
        let i: Int
    }
    @Published private(set) var queue: [Queued] = []
    /// Settings: queueing nests, finishing the last column by itself, and the table background.
    @Published var queueOn: Bool {
        didSet {
            store.set(queueOn, forKey: "native.queueOn")
            if !queueOn { queue = [] }
        }
    }
    @Published var autoAdvance: Bool {
        didSet {
            store.set(autoAdvance, forKey: "native.autoAdvance")
            if !autoAdvance { endBoost() }
        }
    }
    @Published var table: Table { didSet { store.set(table.rawValue, forKey: "native.table") } }
    /// Which screen is up. The board stays loaded while the player is on the home screen, so Play resumes it.
    enum Screen { case home, play }
    @Published var screen: Screen = .home
    @Published var settingsOpen = false
    /// Home's Daily Challenge chooser: clear a Level Play level or a Coin Mining board to keep the streak.
    @Published var dailyPickOpen = false
    /// Settings, saved on this device.
    @Published var hapticsOn: Bool { didSet { store.set(hapticsOn, forKey: "native.haptics") } }
    /// Playback speed at normal and at fast-forward (multiples of the game's base pace).
    @Published var speedNormal: Double { didSet { store.set(speedNormal, forKey: "native.speedNormal") } }
    @Published var speedFast: Double { didSet { store.set(speedFast, forKey: "native.speedFast") } }
    /// The backpack: the tool tray is shown only while it is open.
    @Published var toolsOpen = false
    /// Tools owned (JS wands, owls, drops, xslots, peeks). A new player starts with 3 of each.
    @Published private(set) var tools: [Tool: Int]
    /// The tool whose shop card is up (tapped with none left).
    @Published var shopTool: Tool?
    /// Wise Owl: the next nests to tap, in order (shown as numbered owl badges).
    @Published private(set) var owlPlan: [Queued] = []
    /// Magnifying glass: the lanes show every waiting nest and scroll, until the next tap.
    @Published private(set) var peek = false
    /// Magic wand armed: the next nest tapped (in a lane or a slot) turns magic.
    @Published private(set) var magicMode = false
    /// Acorn Drop is raining.
    @Published private(set) var dropping = false
    /// A short message over the board.
    @Published private(set) var toast: Toast?
    struct Toast: Equatable {
        let id: Int
        let text: String
    }
    /// Falling acorns for the board to draw: the cell each lands on and when it starts falling (media time).
    struct AcornFall {
        let cell: Int
        let start: CFTimeInterval
    }
    private(set) var acornFalls: [AcornFall] = []
    private var dropQueue: [(at: CFTimeInterval, cell: Int)] = []
    /// Extra Slot was used on this board (once per board).
    private(set) var extraUsed = false
    /// History depths at which a wand was spent, so Undo gives the use back.
    private var wandSpentAt: Set<Int> = []
    private var toastID = 0
    @Published private(set) var side = SideState()
    /// Bumped whenever a new board is ready (or restarts), so the board view repaints from scratch.
    @Published private(set) var boardVersion = 0
    /// The 3D scene playing over the stage (intro, lose, win), if any.
    @Published private(set) var scene: SceneRun?
    /// The win or stuck card is up (it appears as the scene fades).
    @Published private(set) var cardShown = false
    @Published private(set) var canUndo = false
    @Published private(set) var coins: Int {
        didSet { if !holdCoins { coinsShown = coins } }
    }
    /// The coin counter as shown: after a win it holds the old amount and counts up as the coins fly in.
    @Published private(set) var coinsShown: Int
    private var holdCoins = false
    private var coinsFrom = 0
    /// Where the win scene's kiss is on the play screen once its coins burst (they fly from there to the counter).
    @Published private(set) var kissCoinsAt: CGPoint?
    /// Counts wins, so each win's coin flight starts fresh.
    @Published private(set) var winCount = 0
    /// Bumped as each flying coin lands on the counter (it pops).
    @Published private(set) var coinLanded = 0
    /// Hearts (Level Play only): one lost per failed or restarted try, one back every 10 minutes, at most 5.
    @Published private(set) var hearts: Int
    /// When the heart now refilling started (seconds since 1970), while hearts are below 5.
    private var regenAt: Double?
    /// Time to the next heart ("9:41"), empty when full.
    @Published private(set) var heartClock = ""
    /// The out-of-hearts card is up; `afterHearts` runs once hearts are bought.
    @Published private(set) var heartsCardShown = false
    private var afterHearts: (() -> Void)?
    /// This try already cost a heart (a loss then a restart costs only one).
    private var attemptCharged = false
    private var heartTimer: Timer?
    static let heartMax = 5
    static let heartRegen: Double = 10 * 60
    static let heartsPrice = 500
    /// When the board now building started, for the intro's progress bar.
    @Published private(set) var buildStarted = Date()
    /// What the last win paid.
    @Published private(set) var lastWin = Win(base: 0, bonus: 0)
    /// The win card's "Next time" choice (nil on warm-up boards).
    @Published private(set) var tailorPick: TailorPick?
    /// Three tries without a win: the next try gets a new, easier board.
    @Published private(set) var easeNext = false
    /// Blocks cleared, all time.
    @Published private(set) var lifetime: Int
    /// This try's mystery boxes on the board (the board view draws them).
    private(set) var pickups: [Pickup] = []
    /// Boxes reached this try (the backpack shows a red dot while they wait).
    @Published private(set) var held: [Held] = []
    /// A tool, Continue or the auto-solver was used this try: every held box is lost.
    @Published private(set) var helped = false
    /// Bumped when a box goes on hold (the backpack's dot pops).
    @Published private(set) var heldPop = 0
    private var boxSource: BoxSource?
    /// This board's boxes, whose pockets were cut into its picture when it was built.
    private var boardPickups: [Pickup] = []
    /// The day the free daily gift was last opened, and the gift being shown now.
    @Published private(set) var giftDay: Int
    @Published private(set) var giftShown: BoxReveal?
    private var boardSeed = 0
    private static let pickedKey = "native.picked"
    /// Board cell size in points, set by the layout (JS sizeBoard).
    var cellSize: CGFloat = 7.5

    /// Every board; grows when new approved boards download (BoardFeed).
    @Published private(set) var catalog: LevelCatalog
    private(set) var level: Level?
    /// The simulation. The board view reads it to draw; only this model changes it.
    private(set) var sim: Sim?
    /// Simulation clock, in ticks (10 ms each).
    private(set) var simT: Double = 0
    private var attempt = 1
    private var history: [Sim] = []
    private var firstTry = true
    private var tailor: Double
    private var tailorBefore: Double = 1
    private var failStreak = 0
    private var buildTask: Task<Void, Never>?
    private let haptics = Haptics()
    /// Ticks a chipmunk stands at its block before heading home with it (a quarter second at normal speed).
    static let pickupPause: Double = 25
    private let notify = UINotificationFeedbackGenerator()

    private static let boardKey = "native.boardIndex"
    /// Set when the player beat the last board there is; cleared when new boards arrive and play moves on to them.
    private static let outOfBoardsKey = "native.outOfBoards"
    /// Bumped if saved data ever needs converting on update. 2.0 reads 1.1's saves as they are (same keys).
    static let saveVersion = 2
    static let continuePrice = 300

    struct SceneRun: Equatable {
        enum Kind { case intro, lose, win }
        let kind: Kind
        let id: Int
    }

    struct Win: Equatable {
        var base: Int
        var bonus: Int
        /// The mystery boxes this win opened (or lost to help).
        var box: BoxReveal? = nil
        /// Daily puzzle: the streak-bonus boxes this win earned.
        var bonusBox: BoxReveal? = nil
        /// This win was the first of the day, so it cleared today's Daily Challenge.
        var dailyCleared = false
    }

    /// Daily streak days that add bonus mystery boxes, and how many (JS STREAK_BONUS).
    static let streakBonus = [3: 1, 7: 2, 14: 3, 30: 5]

    /// What the win card shows of the boxes held at the win: the tools inside, or how many were lost.
    struct BoxReveal: Equatable {
        var tools: [Tool]
        var lost: Bool
        var count: Int { lost ? lostCount : tools.count }
        var lostCount = 0
    }

    /// A box the open area has reached this try: on hold until the board is cleared without help.
    struct Held: Equatable {
        let tool: Tool
        let key: String
    }

    /// Where this board's mystery boxes come from (the picture, its id and its place in the web game's level list).
    struct BoxSource {
        let rows: [String]
        let id: String
        let index: Int
        let board: PickupBoard
    }

    /// Win-card difficulty picks (JS TAILOR).
    enum TailorPick: String, CaseIterable {
        case easier, same, tiny, harder
        var factor: Double {
            switch self {
            case .easier: return 1 / 1.15
            case .same: return 1
            case .tiny: return 1.05
            case .harder: return 1.15
            }
        }
    }

    private var sceneID = 0
    private let store = UserDefaults.standard
    private static let reduceMotion = { UIAccessibility.isReduceMotionEnabled }

    init() {
        var c = try! LevelCatalog.bundled()
        if let saved = BoardFeed.cached { _ = c.merge(feed: saved) }
        catalog = c
        let startCoins = store.object(forKey: "native.coins") == nil ? 500 : store.integer(forKey: "native.coins")
        coins = startCoins
        coinsShown = startCoins
        hearts = store.object(forKey: "native.hearts") == nil ? Self.heartMax
            : min(Self.heartMax, max(0, store.integer(forKey: "native.hearts")))
        regenAt = store.object(forKey: "native.heartRegenAt") == nil ? nil : store.double(forKey: "native.heartRegenAt")
        lifetime = store.integer(forKey: "native.lifetime")
        tailor = store.object(forKey: "native.tailor") == nil ? 1 : store.double(forKey: "native.tailor")
        hapticsOn = store.object(forKey: "native.haptics") == nil ? true : store.bool(forKey: "native.haptics")
        speedNormal = store.object(forKey: "native.speedNormal") == nil ? 1 : store.double(forKey: "native.speedNormal")
        speedFast = store.object(forKey: "native.speedFast") == nil ? 3 : store.double(forKey: "native.speedFast")
        queueOn = store.object(forKey: "native.queueOn") == nil ? true : store.bool(forKey: "native.queueOn")
        autoAdvance = store.object(forKey: "native.autoAdvance") == nil ? true : store.bool(forKey: "native.autoAdvance")
        table = Table(rawValue: store.string(forKey: "native.table") ?? "") ?? .wood
        paraRound = store.integer(forKey: "native.paraRound")
        giftDay = store.object(forKey: "native.giftDay") == nil ? -1 : store.integer(forKey: "native.giftDay")
        daily = (store.data(forKey: "native.daily")).flatMap { try? JSONDecoder().decode(Daily.self, from: $0) } ?? Daily()
        let saved = store.dictionary(forKey: "native.tools") as? [String: Int] ?? [:]
        tools = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, max(0, saved[$0.rawValue] ?? Tool.starting)) })
        boardIndex = min(max(0, store.integer(forKey: Self.boardKey)), c.levelPlay.count - 1)
        store.set(Self.saveVersion, forKey: "native.saveVersion")
        tickHearts()
        heartTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickHearts() }
        }
        #if DEBUG
        // The debug launch arguments (`-scene`, `-autoplay`, `-screen play`) skip the home screen.
        // `-boardFile path.json` ({"name", "rows"}, e.g. from tools/image_to_board.py) plays that picture instead.
        if let file = store.string(forKey: "boardFile"),
           let data = FileManager.default.contents(atPath: file),
           let pic = try? JSONDecoder().decode(ImportedPicture.self, from: data) {
            screen = .play
            loadImported(pic)
        } else if store.string(forKey: "screen") == "dailyPick" {
            dailyPickOpen = true
        } else if store.string(forKey: "scene") != nil || store.bool(forKey: "autoplay") || store.string(forKey: "screen") == "play" {
            screen = .play
            if store.bool(forKey: "fast") { fast = true }
            load(boardIndex)
        }
        #endif
    }

    // MARK: - Screens

    /// The level the home screen offers.
    var homeIndex: Int { boardIndex }

    /// Home's Level Play card: resume the level in progress, or start the next one.
    func playLevel() {
        enterPlay()
        if mode == .level, level != nil, status != .won, !isFailed { return }
        withHeart(level: true) { self.load(self.boardIndex) }
    }

    /// Home's Coin Mining card.
    func playMining() {
        enterPlay()
        if mode == .mining, level != nil, status != .won, !isFailed { return }
        loadMining()
    }

    /// Home's Daily Challenge card (only until today's is cleared): a chooser, since clearing either the next
    /// Level Play level or a Coin Mining board counts.
    func playDaily() {
        guard !dailyDone else { return }
        dailyPickOpen = true
    }

    /// The chooser's two buttons.
    func pickDaily(mining: Bool) {
        dailyPickOpen = false
        if mining { playMining() } else { playLevel() }
    }

    /// The first win of the day clears the Daily Challenge: the streak goes on (or starts again at 1) and streak
    /// days earn bonus mystery boxes. Returns those boxes' tools, or nil when today was already cleared.
    private func creditDaily() -> [Tool]? {
        let day = Self.dayNo()
        guard daily.last != day else { return nil }
        daily.streak = daily.last == day - 1 ? daily.streak + 1 : 1
        daily.count += 1
        daily.last = day
        daily.best = max(daily.best, daily.streak)
        saveDaily()
        var tools: [Tool] = []
        for _ in 0..<(Self.streakBonus[daily.streak] ?? 0) {
            let t = Tool.randomBox()
            tools.append(t)
            addTools(t, 1)
        }
        return tools
    }

    /// Mark the win card when this win cleared today's challenge, with any streak-bonus boxes.
    private func noteDaily(_ tools: [Tool]?) {
        guard let tools else { return }
        lastWin.dailyCleared = true
        if !tools.isEmpty { lastWin.bonusBox = BoxReveal(tools: tools, lost: false) }
    }

    private var isFailed: Bool { if case .failed = status { return true } else { return false } }

    private func enterPlay() {
        toolsOpen = false
        screen = .play
    }

    /// The play screen's home button (and the intro's). The board is kept as it is; nothing is lost, and backing out
    /// of the intro doesn't count as a try.
    func goHome() {
        releaseCoins()
        toolsOpen = false
        shopTool = nil
        screen = .home
    }

    // MARK: - Daily puzzle and Coin Mining

    /// Today's number (JS dayNo): days since 1970 for the local calendar date.
    static func dayNo() -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let d = utc.date(from: c) ?? Date()
        return Int((d.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// Today's daily puzzle (JS dailySetup): the date picks a Level Play picture (from level 6 on) and a board
    /// number on the ramp from 50 to 110, so everyone gets the same board.
    struct DailyBoard {
        let day: Int
        let picture: Int
        let rampN: Int
    }

    var dailyBoard: DailyBoard {
        let day = Self.dayNo()
        let r = RNG(seed: day &* 2_654_435 &+ 11)
        let pool = Array(min(5, catalog.levelPlay.count - 1)..<min(catalog.paradiseFrom, catalog.levelPlay.count))
        let pic = pool[r.int(pool.count)]
        return DailyBoard(day: day, picture: pic, rampN: 50 + r.int(61))
    }

    var dailyDone: Bool { daily.last == Self.dayNo() }
    /// The streak shown: zero once a day has been missed.
    var streakNow: Int { daily.last >= Self.dayNo() - 1 ? daily.streak : 0 }
    /// Daily puzzles are numbered by the player's own count: Day 1 is the first one they clear.
    var dayCount: Int { daily.count + (dailyDone ? 0 : 1) }

    /// The next Coin Mining board.
    var miningBoard: (index: Int, base: LevelBase, seed: Int) { catalog.paradiseRound(paraRound) }

    private func saveDaily() {
        if let d = try? JSONEncoder().encode(daily) { store.set(d, forKey: "native.daily") }
    }

    private func buzz() {
        guard hapticsOn else { return }
        haptics.tap()
    }

    private func buzz(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        if hapticsOn { notify.notificationOccurred(kind) }
    }

    // MARK: - Boards

    /// Load Level Play level i.
    func load(_ i: Int, attempt: Int = 1) {
        mode = .level
        boardIndex = i
        UserDefaults.standard.set(i, forKey: Self.boardKey)
        let key = catalog.diffKey(forBoard: i)
        let aim = LevelCatalog.aim(key, tailor: tailor)
        let baked = attempt == 1 && aim == LevelCatalog.baseAim(key) ? catalog.baked(forBoard: i) : nil
        build(base: catalog.base(forBoard: i), key: key, seed: catalog.seed(forBoard: i, attempt: attempt), aim: aim,
              baked: baked, attempt: attempt, title: catalog.levelPlay[i].name, subtitle: "Level \(i + 1)",
              label: "",
              boxes: BoxSource(rows: catalog.levelPlay[i].rows, id: catalog.levelPlay[i].id, index: i,
                               board: i < 20 ? .warmup(i + 1) : .level(i + 1)))
    }

    /// Load the next Coin Mining board (JS playParadise).
    func loadMining(attempt: Int = 1) {
        mode = .mining
        let b = miningBoard
        build(base: b.base, key: "paradise", seed: b.seed + attempt - 1, aim: LevelCatalog.baseAim("paradise"),
              baked: nil, attempt: attempt, title: b.base.name, subtitle: "Challenge \(paraRound + 1)",
              label: "⛏️ Coin Mining",
              boxes: BoxSource(rows: b.base.rows, id: catalog.paradiseID(forBoard: b.index),
                               index: b.index, board: .mining))
    }

    /// Load today's daily puzzle. It plays on the ramp's settings for its board number, at the standard aim.
    func loadDaily(attempt: Int = 1) {
        mode = .daily
        let d = dailyBoard
        var diff = Difficulty.ramp(d.rampN)
        diff.label = "Daily"
        Difficulty.custom["daily"] = diff
        let p = catalog.levelPlay[d.picture]
        build(base: levelBase(name: p.name, rows: p.rows, boardNumber: d.rampN), key: "daily",
              seed: d.day * 7 + attempt, aim: LevelCatalog.baseAim("daily"), baked: nil, attempt: attempt,
              title: "\(streakNow) 🔥", subtitle: "Current Streak", label: "Daily puzzle",
              boxes: BoxSource(rows: p.rows, id: "daily", index: catalog.paradiseFrom + catalog.paradise.count,
                               board: .daily))
    }

    #if DEBUG
    struct ImportedPicture: Decodable {
        let name: String
        let rows: [String]
    }

    /// Debug: build and play a picture from a file, on the ramp's settings for board 40, with no mystery boxes.
    func loadImported(_ pic: ImportedPicture) {
        mode = .level
        build(base: levelBase(name: pic.name, rows: pic.rows, boardNumber: 40), key: "lv40", seed: 40_007,
              aim: LevelCatalog.baseAim("lv40"), baked: nil, attempt: 1, title: pic.name, subtitle: "Imported",
              label: "Imported picture",
              boxes: BoxSource(rows: pic.rows, id: "import", index: 0, board: .warmup(1)))
    }
    #endif

    /// The same kind of board again with a fresh build (attempt n).
    private func reload(attempt n: Int) {
        switch mode {
        case .level: load(boardIndex, attempt: n)
        case .mining: loadMining(attempt: n)
        case .daily: loadDaily(attempt: n)
        }
    }

    private var loadToken = 0

    private func build(base: LevelBase, key: String, seed: Int, aim: Double, baked: LevelSummary?, attempt: Int,
                       title: String, subtitle: String, label: String, boxes: BoxSource) {
        buildTask?.cancel()
        boxSource = boxes
        boardSeed = seed
        loadToken += 1
        let token = loadToken
        buildStarted = Date()
        self.attempt = attempt
        self.title = title
        self.subtitle = subtitle
        modeLabel = label
        status = .building
        level = nil
        cardShown = false
        easeNext = false
        firstTry = true
        history = []
        canUndo = false
        queue = []
        resetTools()
        stopFast()
        play(.intro)
        // The mystery boxes' pockets are cut out of the picture before the board is built, so its solution plans
        // around them. A pre-built board only fits the uncut picture, so it's used only when there are no boxes.
        let cut = pocketBase(base, id: boxes.id, seed: seed, index: boxes.index, board: boxes.board, claimed: Set(picked))
        boardPickups = cut.pickups
        if let baked, cut.pickups.isEmpty {
            start(assembleLevel(base: base, diffKey: key, seed: seed, summary: baked, aim: aim))
            return
        }
        let cutBase = cut.base
        buildTask = Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) { () -> LevelBox in
                var o = BuildOptions.game
                o.aim = aim
                return LevelBox(generateLevelRetrying(base: cutBase, seed: seed, diffKey: key, options: o))
            }.value
            guard let self, !Task.isCancelled, self.loadToken == token else { return }
            self.buildTask = nil
            if let lv = built.level {
                self.start(lv)
            } else {
                self.status = .failed("Couldn't build a board from this picture.")
            }
        }
    }

    private func start(_ lv: Level) {
        level = lv
        restart()
    }

    /// Play the same board again from the start.
    func restart() {
        guard let lv = level else { return }
        if let s = lv.def?.slots, lv.slots != s { lv.setSlots(s) }
        var m = Sim(lv)
        m.pickupPause = Self.pickupPause
        setupPickups(lv, m)
        sim = m
        simT = 0
        status = .playing
        cardShown = false
        history = []
        canUndo = false
        queue = []
        attemptCharged = false
        releaseCoins()
        resetTools()
        stopFast()
        haptics.wake()
        boardVersion += 1
        refreshSide()
        #if DEBUG
        // `-scene win|lose|card-win|card-stuck` jumps straight to a scene or card (for comparing against the web).
        switch UserDefaults.standard.string(forKey: "scene") {
        case "win": status = .won; payOut(lv); play(.win)
        case "lose": status = .stuck; play(.lose)
        case "card-win": status = .won; payOut(lv); scene = nil; cardShown = true
        case "card-stuck": status = .stuck; scene = nil; cardShown = true
        default: break
        }
        #endif
    }

    /// The card's Restart: a fresh try at the same board (or a new, easier one after three tries without a win).
    func retry() {
        firstTry = false
        withHeart(level: mode == .level) {
            if self.easeNext { self.reload(attempt: self.attempt + 1); return }
            self.restart()
        }
    }

    /// The top bar's restart button counts as a failed try (and costs a heart, unless this try already did).
    func restartButton() {
        firstTry = false
        noteFailure()
        loseHeart()
        withHeart(level: mode == .level) {
            if self.easeNext { self.reload(attempt: self.attempt + 1); return }
            self.restart()
        }
    }

    /// Three losses in a row make Level Play a little easier (the tailored aim). Coin Mining and the daily puzzle
    /// always play at the standard aim.
    private func noteFailure() {
        guard mode == .level else { return }
        failStreak += 1
        if failStreak >= 3 {
            failStreak = 0
            tailor = Self.clampT(tailor / 1.15)
            store.set(tailor, forKey: "native.tailor")
            easeNext = true
        }
    }

    private static func clampT(_ t: Double) -> Double { min(6, max(0.35, t)) }

    /// A different board from the same picture.
    func newBoard() { reload(attempt: attempt + 1) }

    /// The win card's next step: the next level, the next Coin Mining board, or home after the daily puzzle.
    func next() {
        switch mode {
        case .level: withHeart(level: true) { self.load(self.boardIndex) }    // payOut already moved boardIndex on
        case .mining: loadMining()
        case .daily: goHome()
        }
    }

    // MARK: - Playing

    /// Move the clock forward by `dt` seconds of real time.
    func advance(by dt: TimeInterval) {
        guard status == .playing, let lv = level, var m = sim else { return }
        let before0 = simT
        simT += min(dt, 0.1) / SIM.tickSeconds * speed
        advanceTo(lv, &m, simT)
        pickupBuzz(m, from: before0, to: simT)
        rainAcorns(lv, &m)
        if !owlPlan.isEmpty {
            let left = owlPlan.filter { m.s.lp[$0.l] <= $0.i && m.s.tk[$0.l][$0.i] == 0 }
            if left != owlPlan { owlPlan = left }
        }
        // A queued nest loads a quarter second after a slot opens (less at higher speeds), so the hand-off is easy
        // to follow.
        if !queue.isEmpty, canTap(lv, m.s) {
            slotFreeFor += dt
            if slotFreeFor >= Self.queueDelay / speed {
                slotFreeFor = 0
                drainQueue(lv, &m)
            }
        } else {
            slotFreeFor = 0
        }
        autoFinish(lv, &m)
        #if DEBUG
        // Launch with `-autoplay YES` to watch the board play its own stored solution (for testing).
        if UserDefaults.standard.bool(forKey: "autoplay"), canTap(lv, m.s),
           let l = planFrom(lv, m.s.lp)?.first, legalMoves(lv, m.s).contains(l) {
            ChipmunkEngine.tap(lv, &m.s, l)
        }
        #endif
        let before = sim?.s.left ?? m.s.left
        sim = m
        if m.s.left < before {
            lifetime += before - m.s.left
            store.set(lifetime, forKey: "native.lifetime")
        }
        refreshSide()
        checkPickups(m)
        if isCleared(m) {
            status = .won
            stopFast()
            payOut(lv)
            buzz(.success)
            play(.win)
        } else if !dropping, isStuck(lv, &m) {
            status = .stuck
            stopFast()
            firstTry = false
            noteFailure()
            loseHeart()
            buzz(.error)
            play(.lose)
        }
    }

    /// JS payOut, without hearts. (Level Play has no packs, so no pack-completion bonus.)
    private func payOut(_ lv: Level) {
        coinsFrom = coinsShown
        holdCoins = true
        kissCoinsAt = nil
        winCount += 1
        let box = claimHeld()
        defer { lastWin.box = box }
        let c = lv.botWin
        let reward: Int = lv.diff == "paradise" ? 100
            : c == nil ? 100 : Int(JSRound(100 * min(2.5, max(0.6, 0.3 / max(c!, 0.01))) / 10)) * 10
        switch mode {
        case .mining:
            paraRound += 1
            store.set(paraRound, forKey: "native.paraRound")
            lastWin = Win(base: 100, bonus: 0)
            noteDaily(creditDaily())
            tailorPick = nil
            coins += 100
            store.set(coins, forKey: "native.coins")
            return
        case .daily:
            lastWin = Win(base: reward, bonus: 0)
            noteDaily(creditDaily())
            tailorPick = nil
            coins += reward
            store.set(coins, forKey: "native.coins")
            return
        case .level:
            // The next level is the one after this, from now on (finished levels aren't replayed).
            if boardIndex + 1 < catalog.levelPlay.count {
                boardIndex += 1
                store.set(false, forKey: Self.outOfBoardsKey)
            } else {
                // Out of levels: fetch new boards now, and move on to the first one when it arrives.
                store.set(true, forKey: Self.outOfBoardsKey)
                checkForNewBoards()
            }
            store.set(boardIndex, forKey: Self.boardKey)
        }
        let base = reward
        let bonus = firstTry ? Int(JSRound(Double(base) * 0.5)) : 0
        lastWin = Win(base: base, bonus: bonus)
        noteDaily(creditDaily())
        failStreak = 0
        easeNext = false
        if lv.diff?.hasPrefix("warm") == true {
            tailorPick = nil
        } else {
            tailorBefore = tailor
            pickTailor(firstTry ? .tiny : .same)
        }
        coins += base + bonus
        store.set(coins, forKey: "native.coins")
    }

    private var feedTask: Task<Void, Never>?

    /// Download new approved boards if it's time: once a day, or every ten minutes while the player is out of
    /// levels. New boards join the end of Level Play; a player who had run out moves straight on to the first.
    func checkForNewBoards() {
        moveOnToNewBoards()
        let urgent = store.bool(forKey: Self.outOfBoardsKey)
        guard feedTask == nil, BoardFeed.due(urgent: urgent) else { return }
        feedTask = Task { [weak self] in
            let data = await BoardFeed.download()
            guard let self else { return }
            defer { self.feedTask = nil }
            guard let data else { return }
            var c = self.catalog
            guard c.merge(feed: data) > 0 else { return }
            BoardFeed.save(data)
            self.catalog = c
            self.moveOnToNewBoards()
        }
    }

    /// A player who beat the last board moves on to the first new one, unless they're mid-game (then winning that
    /// game moves them on, in payOut, so no board is skipped).
    private func moveOnToNewBoards() {
        guard store.bool(forKey: Self.outOfBoardsKey), screen != .play,
              boardIndex + 1 < catalog.levelPlay.count else { return }
        store.set(false, forKey: Self.outOfBoardsKey)
        boardIndex += 1
        store.set(boardIndex, forKey: Self.boardKey)
    }

    // MARK: - Coin counter

    /// The win card's coins are landing on the counter: show fraction f (0...1) of the win added.
    func countCoins(_ f: Double) {
        guard holdCoins else { return }
        coinsShown = coinsFrom + Int((Double(coins - coinsFrom) * min(1, f)).rounded())
        coinLanded += 1
        if f >= 1 { releaseCoins() }
    }

    /// The win scene's kiss: its coins fly from here to the counter (unless the win card's flight already ran).
    func kissCoins(at p: CGPoint) {
        guard holdCoins, kissCoinsAt == nil else { return }
        kissCoinsAt = p
    }

    /// Whether the counter is waiting on the win card's coins.
    var coinsWaiting: Bool { holdCoins }

    /// The counter catches up to the real amount.
    func releaseCoins() {
        holdCoins = false
        coinsShown = coins
    }

    // MARK: - Hearts

    /// Hearts that have refilled since `regenAt`, and the clock to the next one.
    private func tickHearts() {
        let now = Date().timeIntervalSince1970
        if hearts >= Self.heartMax {
            regenAt = nil
            if !heartClock.isEmpty { heartClock = "" }
            return
        }
        if regenAt == nil { regenAt = now }
        let n = Int(((now - regenAt!) / Self.heartRegen).rounded(.down))
        if n > 0 {
            hearts = min(Self.heartMax, hearts + n)
            regenAt = hearts >= Self.heartMax ? nil : regenAt! + Double(n) * Self.heartRegen
            saveHearts()
        }
        guard let r = regenAt else { heartClock = ""; return }
        let left = max(0, Int((Self.heartRegen - (now - r)).rounded(.up)))
        let text = "\(left / 60):" + String(format: "%02d", left % 60)
        if text != heartClock { heartClock = text }
    }

    private func saveHearts() {
        store.set(hearts, forKey: "native.hearts")
        if let regenAt { store.set(regenAt, forKey: "native.heartRegenAt") } else { store.removeObject(forKey: "native.heartRegenAt") }
    }

    /// A Level Play try was lost or restarted: one heart, at most once per try.
    private func loseHeart() {
        guard mode == .level, !attemptCharged else { return }
        attemptCharged = true
        if hearts >= Self.heartMax { regenAt = Date().timeIntervalSince1970 }
        hearts = max(0, hearts - 1)
        saveHearts()
        tickHearts()
    }

    /// Run `then` if a Level Play try can start; with no hearts left, show the out-of-hearts card instead (buying
    /// hearts there runs it).
    private func withHeart(level: Bool, _ then: @escaping () -> Void) {
        tickHearts()
        if !level || hearts > 0 {
            then()
            return
        }
        afterHearts = then
        heartsCardShown = true
    }

    /// The out-of-hearts card's buy button: 5 hearts for 500 coins, then the try goes ahead.
    func buyHearts() {
        guard coins >= Self.heartsPrice else { return }
        coins -= Self.heartsPrice
        store.set(coins, forKey: "native.coins")
        hearts = Self.heartMax
        regenAt = nil
        saveHearts()
        tickHearts()
        heartsCardShown = false
        buzz(.success)
        let go = afterHearts
        afterHearts = nil
        go?()
    }

    /// A heart refilled while the out-of-hearts card was up: the try goes ahead.
    func heartArrived() {
        guard heartsCardShown, hearts > 0 else { return }
        heartsCardShown = false
        let go = afterHearts
        afterHearts = nil
        go?()
    }

    /// The out-of-hearts card's Home button.
    func closeHeartsCard() {
        heartsCardShown = false
        afterHearts = nil
        goHome()
    }

    /// Win card choice: re-applies from the target before this win, so picks replace each other.
    func pickTailor(_ k: TailorPick) {
        tailorPick = k
        tailor = Self.clampT(tailorBefore * k.factor)
        store.set(tailor, forKey: "native.tailor")
    }

    // MARK: - Scenes

    private func play(_ kind: SceneRun.Kind) {
        if Self.reduceMotion() {
            scene = nil
            cardShown = kind != .intro
            return
        }
        sceneID += 1
        scene = SceneRun(kind: kind, id: sceneID)
    }

    /// The scene has played through (or was skipped): the card appears under it while it fades.
    func sceneFinished(_ run: SceneRun) {
        guard scene == run else { return }
        if run.kind != .intro { cardShown = true }
    }

    /// The scene has faded out.
    func sceneGone(_ run: SceneRun) {
        if scene == run { scene = nil }
    }

    /// Whether the intro may end (the board is built).
    var introReady: Bool { status != .building }

    // MARK: - Undo and continue

    func undo() {
        guard level != nil, !history.isEmpty else { return }
        if wandSpentAt.remove(history.count) != nil { addTools(.wand, 1) }
        let m = history.removeLast()
        queue = []
        owlPlan = []
        stopDrop()
        if peek { peek = false }
        firstTry = false
        sim = m
        simT = m.tick
        canUndo = !history.isEmpty
        status = .playing
        cardShown = false
        scene = nil
        boardVersion += 1
        refreshSide()
    }

    /// After getting stuck: 300 coins empties 3 slots chosen at random and takes those nests' blocks off the board.
    func continueGame() {
        guard status == .stuck, coins >= Self.continuePrice, let lv = level, var m = sim else { return }
        coins -= Self.continuePrice
        store.set(coins, forKey: "native.coins")
        firstTry = false
        markHelp()
        history.append(m)
        canUndo = true
        let before = m.s.left
        rescueSlots(lv, &m.s, RNG(seed: (Int(Date().timeIntervalSince1970 * 1000) & 0xFFFF) + history.count), 3)
        lifetime += before - m.s.left
        store.set(lifetime, forKey: "native.lifetime")
        sim = m
        status = .playing
        cardShown = false
        scene = nil
        boardVersion += 1
        buzz()
        refreshSide()
        checkPickups(m)
        if m.s.left == 0 {
            status = .won
            stopFast()
            payOut(lv)
            cardShown = true
        }
    }

    /// Tap lane l: its front nest moves into a free slot. Returns false when that isn't possible right now.
    @discardableResult
    func tap(lane l: Int) -> Bool {
        guard status == .playing, let lv = level, var m = sim else { return false }
        guard legalMoves(lv, m.s).contains(l) else { return false }
        history.append(m)
        canUndo = true
        ChipmunkEngine.tap(lv, &m.s, l)
        sim = m
        buzz()
        refreshSide()
        return true
    }

    private func refreshSide() {
        guard let lv = level, let m = sim else { return }
        var s = SideState()
        s.columns = lv.def?.slots ?? lv.slots
        s.slots = (0..<lv.slots).map { k in
            m.s.sl.first { $0.k == k }.map { SideState.SlotItem(c: $0.c, r: $0.r, key: $0.key, magic: $0.w) }
        }
        s.lockedAt = m.s.locked ? lv.lockAt : nil
        for (l, lane) in lv.lanes.enumerated() {
            let p = m.s.lp[l]
            if p >= lane.count { continue }   // an empty lane drops out; the rest slide together
            var nests = [lane[p]], at = [p]
            var k = p + 1
            while k < lane.count && (peek || nests.count < 4) {
                if m.s.tk[l][k] == 0 {
                    nests.append(lane[k])
                    at.append(k)
                }
                k += 1
            }
            s.lanes.append(SideState.Lane(id: l, nests: nests, at: at))
        }
        if s != side { side = s }
    }

    // MARK: - Speed

    /// The playback speed now: normal or fast-forward.
    private var speed: Double { fast ? speedFast : speedNormal }

    /// The fast-forward button. A change by the player sticks, even over the last-column boost.
    func toggleFast() {
        boostFrom = nil
        fast.toggle()
    }

    /// While the last column finishes by itself the game runs at fast-forward. This is the speed the player had
    /// before; it comes back on the next board, a restart, or when auto-finish is turned off.
    private var boostFrom: Bool?

    private func endBoost() {
        if let b = boostFrom { fast = b }
        boostFrom = nil
    }

    /// A board ends (won or stuck), restarts, or a new one loads: fast-forward goes off, so each game starts at
    /// normal speed and the player turns it on themselves.
    private func stopFast() {
        boostFrom = nil
        fast = false
    }

    // MARK: - Nest queue (JS preQ) and auto-finish

    static let queueMax = 9
    private static let queueDelay = 0.25
    private static let doubleTap = 0.32
    private var slotFreeFor = 0.0
    private var lastPress = (key: "", at: 0.0, wasQueued: false)

    /// Queue position (from 1) of nest i in lane l, if it's queued.
    func queuePlace(lane l: Int, at i: Int) -> Int? {
        queue.firstIndex(of: Queued(l: l, i: i)).map { $0 + 1 }
    }

    /// A finger lands on nest i of lane l (JS onLanePress). With a free slot the front nest loads now. When every
    /// slot is full (or the nest is further back) it lines up, along with the nests in front of it, to load as
    /// slots open, up to 9 in all. Double-tapping a queued nest takes just that one out of the line.
    func press(lane l: Int, at i: Int) {
        guard status == .playing, let lv = level, var m = sim else { return }
        if magicMode {
            wandLane(lv, &m, l, i)
            return
        }
        if peek {
            peek = false
            refreshSide()
        }
        if let first = owlPlan.first {
            if first == Queued(l: l, i: i) { owlPlan.removeFirst() } else { owlPlan = [] }
        }
        let now = CACurrentMediaTime(), key = "\(l):\(i)"
        let full = !canTap(lv, m.s)
        let at = queue.firstIndex(of: Queued(l: l, i: i))
        if key == lastPress.key, now - lastPress.at < Self.doubleTap, lastPress.wasQueued, let at {
            queue.remove(at: at)
            lastPress.key = ""
            buzz()
            return
        }
        lastPress = (key, now, at != nil)
        if !queueOn, full || i > m.s.lp[l] { return }        // queueing off: only a free slot takes a nest
        if !full, i <= m.s.lp[l] {                          // the front nest and a slot is free: load it now
            tap(lane: l)
            return
        }
        if at != nil { return }                             // already queued
        var add: [Queued] = []
        for k in m.s.lp[l]...i where queue.firstIndex(of: Queued(l: l, i: k)) == nil && m.s.tk[l][k] == 0 {
            add.append(Queued(l: l, i: k))
        }
        if queue.count + add.count > Self.queueMax { return }
        queue += add
        buzz()
        if !full {
            drainQueue(lv, &m)
            sim = m
            refreshSide()
        }
    }

    /// Load queued nests into free slots, in line order: the first one that's at the front of its lane goes next.
    private func drainQueue(_ lv: Level, _ m: inout Sim) {
        queue.removeAll { q in !(m.s.lp[q.l] <= q.i && q.i < lv.lanes[q.l].count && m.s.tk[q.l][q.i] == 0) }
        while canTap(lv, m.s), let k = queue.firstIndex(where: { m.s.lp[$0.l] == $0.i }) {
            let q = queue.remove(at: k)
            guard legalMoves(lv, m.s).contains(q.l) else { continue }
            history.append(m)
            canUndo = true
            ChipmunkEngine.tap(lv, &m.s, q.l)
            buzz()
        }
    }

    /// The one lane that still has nests, if only one does.
    private func lastColumn(_ lv: Level, _ s: State) -> Int? {
        var one: Int?
        for l in lv.lanes.indices where s.lp[l] < lv.lanes[l].count {
            if one != nil { return nil }
            one = l
        }
        return one
    }

    /// Auto-finish: once only one lane has nests left there's no choice to make, so its nests load on their own
    /// whenever a slot is free, at fast-forward.
    private func autoFinish(_ lv: Level, _ m: inout Sim) {
        guard autoAdvance, let l = lastColumn(lv, m.s) else { return }
        if !fast {
            if boostFrom == nil { boostFrom = false }
            fast = true
        }
        while canTap(lv, m.s), m.s.lp[l] < lv.lanes[l].count, legalMoves(lv, m.s).contains(l) {
            queue = []
            history.append(m)
            canUndo = true
            ChipmunkEngine.tap(lv, &m.s, l)
            buzz()
        }
    }

    // MARK: - Tools (JS BACKPACK)

    /// Using any tool ends the first-try bonus for this try. The wand is spent when it touches a nest.
    func use(_ t: Tool) {
        guard count(t) > 0, canUse(t), let lv = level, var m = sim else { return }
        toolsOpen = false
        if t == .wand {
            magicMode = true
            buzz()
            return
        }
        firstTry = false
        markHelp()
        addTools(t, -1)
        switch t {
        case .owl:
            say("🦉 Thinking…")
            // The solver gets its own copy of the level: routing uses scratch buffers stored on the Level, and the
            // live game is routing critters on the main thread at the same time (a shared Level crashed the app).
            let box = LevelBox(lv.copy()), start = m, token = loadToken
            Task { [weak self] in
                let r = await Task.detached(priority: .userInitiated) { solve(box.level!, start) }.value
                guard let self, self.loadToken == token, self.status == .playing, let now = self.sim else { return }
                if let path = r.path, !path.isEmpty {
                    self.owlPlan = Self.owlSteps(now.s, path, 3)
                    self.say("🦉 Tap the nests in order: 1, 2, 3")
                } else {
                    self.addTools(.owl, 1)
                    self.say("🦉 No winning line from here. Try Undo.")
                }
            }
        case .peek:
            peek = true
            refreshSide()
        case .slot:
            extraUsed = true
            lv.setSlots(lv.slots + 1)
            buzz()
            refreshSide()
            say("Extra slot added")
        case .drop:
            history.append(m)
            canUndo = true
            dropping = true
            let now = CACurrentMediaTime(), N = lv.W * lv.H
            for k in 0..<Self.acornCount {
                let cell = Int.random(in: 0..<N), start = now + Double(k) * Self.acornGap
                acornFalls.append(AcornFall(cell: cell, start: start))
                dropQueue.append((start + Self.acornFall, cell))
            }
            sim = m
        case .wand:
            break
        }
    }

    /// The tool bar button for t: with some left, use it; with none, open its shop card. The armed wand and the open
    /// magnifying glass put themselves away.
    func toolTapped(_ t: Tool) {
        if t == .wand && magicMode {
            magicMode = false
            buzz()
            return
        }
        if t == .peek && peek {
            peek = false
            refreshSide()
            return
        }
        if count(t) == 0 { shopTool = t }
    }

    func count(_ t: Tool) -> Int { tools[t] ?? 0 }

    func canUse(_ t: Tool) -> Bool {
        guard level != nil, status == .playing else { return false }
        switch t {
        case .peek: return !peek
        case .slot: return !extraUsed
        case .drop: return !dropping
        case .wand: return !magicMode
        case .owl: return true
        }
    }

    func buy(_ t: Tool) {
        guard coins >= t.price else { return }
        coins -= t.price
        store.set(coins, forKey: "native.coins")
        addTools(t, t.pack)
        shopTool = nil
        buzz()
    }

    func cancelWand() {
        magicMode = false
    }

    /// The backpack button (and a tap on the board): put an armed wand away, or show or hide the tools.
    func toggleBackpack() {
        if magicMode { cancelWand() } else { toolsOpen.toggle() }
    }

    /// The light tap used for small confirmations.
    func lightTap() { buzz() }

    private func addTools(_ t: Tool, _ n: Int) {
        tools[t] = max(0, count(t) + n)
        store.set(Dictionary(uniqueKeysWithValues: tools.map { ($0.key.rawValue, $0.value) }), forKey: "native.tools")
    }

    private func resetTools() {
        owlPlan = []
        peek = false
        magicMode = false
        extraUsed = false
        wandSpentAt = []
        stopDrop()
    }

    private func say(_ text: String) {
        toastID += 1
        let id = toastID
        toast = Toast(id: id, text: text)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if self?.toast?.id == id { self?.toast = nil }
        }
    }

    /// The solver's next n taps as nests (a lane tapped twice gets its front nest and then the one behind it).
    private static func owlSteps(_ s: State, _ path: [Int], _ n: Int) -> [Queued] {
        var lp = s.lp, out: [Queued] = []
        for l in path where out.count < n {
            var i = lp[l]
            while i < s.tk[l].count && s.tk[l][i] != 0 { i += 1 }
            out.append(Queued(l: l, i: i))
            lp[l] = i + 1
        }
        return out
    }

    /// Wand on a lane nest: the front one, or one further back pulled straight out of its column. It needs a free slot.
    private func wandLane(_ lv: Level, _ m: inout Sim, _ l: Int, _ i: Int) {
        guard i >= m.s.lp[l], i < lv.lanes[l].count, m.s.tk[l][i] == 0 else { return }
        guard canTap(lv, m.s) else {
            say("No free slot: tap a nest in a slot, or wait for one to open")
            return
        }
        history.append(m)
        wandSpentAt.insert(history.count)
        canUndo = true
        let id = tapAt(lv, &m.s, l, i)
        if id != 0 { makeMagic(&m.s, id: id) }
        spendWand()
        queue.removeAll { $0 == Queued(l: l, i: i) }
        owlPlan = []
        sim = m
        refreshSide()
    }

    /// Wand on a nest already in slot k: from now on its chipmunks fly.
    func wandSlot(_ k: Int) {
        guard magicMode, status == .playing, var m = sim,
              let n = m.s.sl.first(where: { $0.k == k }), !n.w else { return }
        history.append(m)
        wandSpentAt.insert(history.count)
        canUndo = true
        makeMagic(&m.s, id: n.id)
        spendWand()
        sim = m
        refreshSide()
    }

    private func spendWand() {
        addTools(.wand, -1)
        magicMode = false
        firstTry = false
        markHelp()
        buzz()
    }

    // MARK: - Acorn Drop

    static let acornCount = 75
    /// 75 acorns over about 5 seconds; each takes 0.42 s to fall.
    static let acornGap = 5.0 / 75
    static let acornFall = 0.42

    private func rainAcorns(_ lv: Level, _ m: inout Sim) {
        guard dropping else { return }
        let now = CACurrentMediaTime()
        while let d = dropQueue.first, d.at <= now {
            dropQueue.removeFirst()
            if acornHit(lv, &m.s, d.cell) {
                lifetime += 1
                store.set(lifetime, forKey: "native.lifetime")
                buzz()
            }
        }
        acornFalls.removeAll { now - $0.start > Self.acornFall + 0.3 }
        if dropQueue.isEmpty {
            dropping = false
            refreshSide()
        }
    }

    private func stopDrop() {
        dropQueue = []
        acornFalls = []
        dropping = false
    }

    // MARK: - Mystery boxes (JS setupPickups, checkPickups, markHelp, claimHeld)

    /// Keys of boxes already opened, oldest first (the newest 500 are kept).
    private var picked: [String] { store.stringArray(forKey: Self.pickedKey) ?? [] }

    /// A new try: the boxes go back on the board (any not opened on an earlier win) and nothing is on hold.
    /// A new try: this board's boxes go back in their pockets (any opened on an earlier win stay opened) and nothing
    /// is on hold.
    private func setupPickups(_ lv: Level, _ m: Sim) {
        held = []
        helped = false
        let opened = Set(picked)
        pickups = boardPickups.map { p in
            var q = p
            q.got = p.claimed || opened.contains(p.key)
            return q
        }
    }

    /// The critters' open area has reached a pocket: its box goes on hold.
    private func checkPickups(_ m: Sim) {
        for k in pickups.indices where !pickups[k].got && pickups[k].reached(m.s) {
            pickups[k].got = true
            guard let t = Tool(rawValue: pickups[k].tool) else { continue }
            held.append(Held(tool: t, key: pickups[k].key))
            heldPop += 1
            buzz()
        }
    }

    /// A tool, Continue or the auto-solver: every box held (or reached later) this try is lost.
    private func markHelp() {
        guard !helped else { return }
        helped = true
        if !held.isEmpty {
            say(held.count > 1 ? "Mystery boxes lost: help was used" : "Mystery box lost: help was used")
            buzz(.warning)
        }
    }

    /// The free daily gift (one mystery box) hasn't been opened today.
    var giftReady: Bool { giftDay != Self.dayNo() }

    /// Open today's gift: a random tool goes in the backpack, shown with the box reveal.
    func openGift() {
        guard giftReady else { return }
        giftDay = Self.dayNo()
        store.set(giftDay, forKey: "native.giftDay")
        let t = Tool.randomBox()
        addTools(t, 1)
        giftShown = BoxReveal(tools: [t], lost: false)
        buzz(.success)
    }

    func closeGift() { giftShown = nil }


    /// The win opens the held boxes: their tools go in the backpack, and they're remembered as opened.
    private func claimHeld() -> BoxReveal? {
        guard !held.isEmpty else { return nil }
        let hs = held
        held = []
        if helped { return BoxReveal(tools: [], lost: true, lostCount: hs.count) }
        var keys = picked
        for h in hs {
            if !keys.contains(h.key) { keys.append(h.key) }
            addTools(h.tool, 1)
        }
        store.set(Array(keys.suffix(500)), forKey: Self.pickedKey)
        return BoxReveal(tools: hs.map(\.tool), lost: false)
    }

    // MARK: - Pickup haptic

    /// A click as a chipmunk reaches its block.
    private func pickupBuzz(_ m: Sim, from t0: Double, to t1: Double) {
        guard hapticsOn else { return }
        guard m.ants.contains(where: { $0.picked && $0.ta > t0 && $0.ta <= t1 }) else { return }
        haptics.pickup()
    }

    // MARK: - Looks

    /// RGB of color index c on this board.
    func hex(_ c: Int) -> UInt32 { level?.rgb(c) ?? 0x888888 }

    /// Difficulty tier (JS TIERS): acorn count from the careful player's win rate.
    var tier: Int? {
        guard let c = level?.botWin else { return nil }
        return c >= 0.5 ? 1 : c >= 0.35 ? 2 : c >= 0.22 ? 3 : c >= 0.12 ? 4 : 5
    }

    /// Difficulty shown to the player: acorns from the careful player's win rate (JS TIERS / acorns).
    var acorns: String {
        guard let c = level?.botWin else { return "–" }
        let n = c >= 0.5 ? 1 : c >= 0.35 ? 2 : c >= 0.22 ? 3 : c >= 0.12 ? 4 : 5
        return String(repeating: "🌰", count: n)
    }
}

/// Carries a built Level out of the background task (Level is a class the builder no longer touches).
private struct LevelBox: @unchecked Sendable {
    let level: Level?
    init(_ level: Level?) { self.level = level }
}

/// The backpack's tools (JS TOOLS), in tool bar order.
enum Tool: String, CaseIterable, Identifiable {
    case owl, peek, drop, slot, wand

    var id: String { rawValue }
    /// A tool for a mystery box, with the boxes' odds.
    static func randomBox() -> Tool { Tool(rawValue: randTool(Double.random(in: 0..<1))) ?? .owl }
    /// How many of each a new player starts with.
    static let starting = 3

    var icon: String {
        switch self {
        case .owl: return "🦉"
        case .peek: return "🔍"
        case .drop: return "🌰"
        case .slot: return "➕"
        case .wand: return "🪄"
        }
    }

    var name: String {
        switch self {
        case .owl: return "Wise Owl"
        case .peek: return "Magnifying Glass"
        case .drop: return "Acorn Drop"
        case .slot: return "Extra Slot"
        case .wand: return "Magic Wand"
        }
    }

    /// How many one purchase gives, and for how many coins.
    var pack: Int {
        switch self {
        case .owl: return 3
        case .peek, .wand: return 5
        case .drop, .slot: return 1
        }
    }

    var price: Int {
        switch self {
        case .owl: return 100
        case .peek, .drop: return 150
        case .slot: return 250
        case .wand: return 750
        }
    }

    var desc: String {
        switch self {
        case .owl: return "Shows the next 3 nests to tap, in order."
        case .peek: return "Scroll the queue to see every nest past row 3, until your next tap."
        case .drop: return "75 acorns rain down over 5 seconds and knock out the blocks they hit."
        case .slot: return "A 6th holding slot for the rest of this board."
        case .wand: return "Tap a nest: its chipmunks fly straight to their color."
        }
    }
}
