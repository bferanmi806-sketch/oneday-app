import SwiftUI
import UIKit

/// 聊天行高量测的线程分发原语（§331，0.50.70
/// 热修题 3 根治）：主线程走现行量测视图（§168
/// 共享台——同步路径与既有全部口径逐值不变）；
/// 后台线程走 §251 后台量测池的每线 TextKit 2
/// 栈（与量测视图同引擎、影子对拍自 2026-11-14
/// 在产验证）。合成器核心据此成为线程无关的纯
/// 量测，可在量测台队列整行执行——主线程自此
/// 只在同步兜底路径上量测（直播行等少数行），
/// 历史行全量走后台预排版
enum ChatNativeTextMeasure {
    /// 给定宽下的高。emptyLineHeight＝空串口径：
    /// 量测视图对空串回字体一行高（§168/§329 校
    /// 准口径），池对空串不造数——后台路径以调
    /// 用方给出的字体行高补齐，两路同值
    static func height(
        attributed: NSAttributedString, width: CGFloat,
        emptyLineHeight: CGFloat
    ) -> CGFloat {
        if Thread.isMainThread {
            return SelectableTextRepresentable
                .referenceHeight(
                    attributed: attributed, width: width
                )
        }
        guard attributed.length > 0 else {
            return emptyLineHeight
        }
        return LayoutMeasurePool.shared
            .measureSizeSynchronously(
                attributed, width: width
            ).height
    }

    /// 自然单行宽（表格列宽/时间列宽用）：与量测
    /// 视图同口径——无提议宽时按 10_000 宽量一
    /// 行、取其宽
    static func naturalWidth(
        attributed: NSAttributedString
    ) -> CGFloat {
        if Thread.isMainThread {
            return SelectableTextRepresentable
                .measuredSize(
                    attributed: attributed,
                    proposal: ProposedViewSize(
                        width: nil, height: nil
                    )
                ).width
        }
        guard attributed.length > 0 else { return 0 }
        return LayoutMeasurePool.shared
            .measureSizeSynchronously(
                attributed, width: 10_000
            ).width
    }
}
