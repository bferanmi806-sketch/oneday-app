import OneDayCore
import OneDayDesign
import SwiftUI

/// 定时任务只读行（台账 198 收敛·行件合一）：枢纽
/// 定时段与状态页定时摘录共用同一行件——此前两面
/// 各绘一份（枢纽自绘带方片/圆盘、状态页自绘纯文
/// 字行），数据合一（CronStore）后呈现也只许一种。
/// 行型：提醒/每日用日历方片＋琥珀角标（L5），间隔
/// 用时钟圆盘；文案口径（数据设计 §3.4）：时间一
/// 律走 nextRunAt 绝对时刻，取不到回落 scheduleText，
/// 不编造。本体自 HubCronSection 原行抽出、逐值不变。
struct CronOverviewRow: View {
    let item: HubCronItem

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            switch item.kind {
            case .reminder, .daily, .otherRecurring:
                calendarTile(withBadge: item.kind != .otherRecurring)
            case .interval:
                clockDisc
            }
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                HStack(spacing: OneDayMetrics.rowInnerGap) {
                    Text(item.job.title)
                        .font(.body)
                        .foregroundStyle(
                            item.job.enabled ? Palette.ink : Palette.inkSecondary
                        )
                        .lineLimit(1)
                    if !item.job.enabled {
                        Text("已暂停")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                ForEach(textLines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// 行文案（数据设计 §3.4）
    private var textLines: [String] {
        switch item.kind {
        case .reminder:
            guard let next = item.nextRunAt else {
                return [item.job.scheduleText]
            }
            return [
                AdminFormat.day(next),
                AdminFormat.timeOnly(next),
            ]
        case .daily:
            guard let next = item.nextRunAt else {
                return [item.job.scheduleText]
            }
            return [AdminFormat.timeOnly(next)]
        case .interval:
            var lines: [String] = []
            if let intervalText = item.intervalText {
                lines.append(intervalText)
            } else {
                lines.append(item.job.scheduleText)
            }
            if let last = item.lastRunAt {
                lines.append("上次运行 \(last.formatted(.relative(presentation: .named)))")
            }
            return lines
        case .otherRecurring:
            var lines = [item.job.scheduleText]
            if let next = item.nextRunAt {
                lines.append(AdminFormat.short(next))
            }
            return lines
        }
    }

    /// 日历方片＋右下琥珀时钟角标（L5，用户定案④打
    /// 包；角标色 #E6B036 依基线补遗，暗色给同系深值）
    private func calendarTile(withBadge: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusThumb)
                    .fill(Palette.surface)
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusThumb)
                    .stroke(Palette.hairline, lineWidth: 0.5)
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 44, height: 44)

            if withBadge {
                // 0.36.0（无障碍 A11Y-D2 部分）：角标
                // 字形原 8pt 过小——徽标 16→18、字形
                // 8→10 放大一档（图形角标非文字，放大
                // 后仍属装饰级尺寸，已在台账注明）
                ZStack {
                    Circle().fill(Self.amber)
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
                .offset(x: 4, y: 4)
            }
        }
        .frame(width: 48, height: 48)
    }

    /// 间隔行时钟圆盘（规格 #34：细线表盘拼装）
    private var clockDisc: some View {
        ZStack {
            Circle().stroke(Palette.hairline, lineWidth: 1)
            Image(systemName: "clock")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Palette.ink)
        }
        .frame(width: 44, height: 44)
        .frame(width: 48, height: 48)
    }

    private static let amber = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xC9 / 255.0, green: 0x96 / 255.0, blue: 0x2E / 255.0, alpha: 1)
            : UIColor(red: 0xE6 / 255.0, green: 0xB0 / 255.0, blue: 0x36 / 255.0, alpha: 1)
    })
}
