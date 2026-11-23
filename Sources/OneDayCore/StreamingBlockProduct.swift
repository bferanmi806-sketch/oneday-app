import Foundation

/// §247（2026-11-14）流式块级增量产物（换代包 4）
///
/// 出处：native-list-migration-blueprint-20261113.md
/// §1.4＋§2 包 4。蓝图口径：流式与落定同一条管线
/// ——流式条目是一个普通快照条目，其产物按 markdown
/// 块增量生长：已闭合的块产物冻结、只有未闭合的尾
/// 块重算；落定＝同一条目产物补齐最后一块＋状态位
/// 翻转、无视图树换装。
///
/// 本文件是这条管线的 Core 面（纯值与纯函数）：
/// - 块切分/块产物身份（StreamingBlockSegmen-
///   ter／StreamingBlockIdentity 等）：§409 步
///   C/D 已退役删除（流式呈现退役后无消费方；
///   落定侧从不消费本簇，结构源仍是 Markdown-
///   Parser 本体）。
/// - 行身份与落定映射（StreamingRowIdentity／
///   StreamingSettleMap）：流式行以本轮用户条目 id
///   为键，落定新建的助手条目沿用同一键在承载侧
///   原位 reconfigure，即「落定不换装」的身份基础。
/// - 流式呈现开关（ChatStreamingFeature）：新路
///   （块级增量）与旧路（TokenFlow 逐词元全量
///   arrange）的独立回滚开关，包 6 清理。
///
/// 行高口径与主线裁定一致（包 3 登记待裁已裁）：
/// 产物估算起步＋托管量实回填覆盖同 key 估算、量
/// 实不落盘（WWDC19 estimated 同构）——块产物只
/// 喂估算侧，量实覆盖在承载侧（ChatListCarrier），
/// 本文件不持任何量实值。

// MARK: - 流式呈现开关（回滚路）

/// 流式呈现路径开关（蓝图 §2 包 4 回滚条款：流式
/// 呈现路径独立开关回 TokenFlow 旧路、保留一包、
/// 包 6 清理）。UserDefaults 布尔键，**缺省 true**
/// ＝块级增量新路（本包交付物即默认形态）；显式
/// false 才回旧路——与 ChatCarrierFeature 的缺省
/// false 方向相反，因为本键管的是呈现算法而非承
/// 载：承载默认旧（包 3 开关）时本键无消费方，承
/// 载切新后呈现默认走新路、出问题单独关本键即回
/// 逐词渐显，不必连承载一并退回
public enum ChatStreamingFeature {
    public static let defaultsKey = "chat.streaming.gen4"

    public static func isIncrementalEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil
        else { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}

// MARK: - 打字动画开关与入场计划（第 104 条）

/// 打字动画开关（2026-11-15 流式块级口径拍板时备好
/// 的规格、2026-11-16 第 104 条落地）：设置→外观
/// 「回复呈现」节的「打字动画」。UserDefaults 布尔
/// 键，**缺省 true**＝流式新词元带单次轻渐显；显式
/// false＝整批直显。Reduce Motion 不读本键——它在
/// 入场计划层优先于本开关（见 StreamingEntrance），
/// 本键只表达用户口味、不表达无障碍需求
public enum StreamingTypewriterFeature {
    public static let defaultsKey = "chat.streaming.typewriter"

    public static func isEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil
        else { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}

/// 流式词元入场计划（第 104 条到达减法，纯函数单点
/// 裁定）：到达瞬间只许一个主动画——
///
/// - 首批（本代次尚无任一词元已显形，含指示器退场
///   的换装拍与换代重发）：**整批直显**。指示器与正
///   文同拍交接、不许出现「内容不可见而占位已全
///   宽」的光标药丸帧，正文以最终落位静态出现
/// - 开关关或 Reduce Motion：全程整批直显（Reduce
///   Motion 优先于开关）
/// - 其余批次：整批同拍单次轻渐显（batchFade）——
///   同批词元共享一次 opacity 渐显，不逐词元错开、
///   不带 blur；已显形词元永不重演
public enum StreamingEntrance {
    public enum Plan: Equatable, Sendable {
        case instant
        case batchFade
    }

    public static func plan(
        typewriterEnabled: Bool,
        reduceMotion: Bool,
        isFirstBatchOfGeneration: Bool
    ) -> Plan {
        guard typewriterEnabled, !reduceMotion,
              !isFirstBatchOfGeneration
        else { return .instant }
        return .batchFade
    }
}

// MARK: - 行身份与落定映射

/// 流式行键：以本轮用户条目 id 为身份（发送互斥
/// 保证同线程同刻只有一轮在飞，用户条目 id 即回
/// 合的稳定身份）。落定新建的助手条目沿用此键，
/// 承载侧据键认行——同键＋版本变＝原位 recon-
/// figure，这就是「落定不换装」在本承载（手动
/// 帧布局＋托管窗口）的等价实现
public enum StreamingRowIdentity {
    public static func streamRowKey(
        userEntryID: String
    ) -> String {
        "stream-\(userEntryID)"
    }

    /// 账本缺位时的回落键（演示种子轮等无账本轮
    /// 次）：线程内唯一在飞轮的回落身份，落定映
    /// 射同以此键登记
    public static func fallbackStreamRowKey(
        threadID: UUID
    ) -> String {
        "stream-thread-\(threadID.uuidString)"
    }
}

/// 落定映射（会话内记账、不落盘）：助手条目 id
/// → 其流式行键。落定时由落定口登记（applySet-
/// tledTurn 建条目处），行构建时查询（条目行键
/// 优先取映射、缺位回本名）。守则：同一流式行
/// 键只许被一个条目认领（首个登记者得）——重发
/// 同一用户条目的第二轮落定时若首轮条目尚在，
/// 次轮不抢键、按本名建行（降级为常规换行，无
/// 正确性问题）；首轮条目已被整段替换删除的情
/// 形下映射随条目消亡由构建侧自然失效（查不到
/// 对应在列条目时映射不参与）
public struct StreamingSettleMap: Equatable, Sendable {
    private var rowKeyByEntryID: [UUID: String] = [:]
    private var claimedKeys: Set<String> = []

    public init() {}

    @discardableResult
    public mutating func record(
        entryID: UUID, streamRowKey: String
    ) -> Bool {
        guard !claimedKeys.contains(streamRowKey) else {
            return false
        }
        claimedKeys.insert(streamRowKey)
        rowKeyByEntryID[entryID] = streamRowKey
        return true
    }

    public func rowKey(for entryID: UUID) -> String? {
        rowKeyByEntryID[entryID]
    }

    public var count: Int { rowKeyByEntryID.count }
}
