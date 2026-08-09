//
//  AboutSheet.swift
//  anitabi
//
//  HomeSheet「⋯」メニューの「关于」。設計稿 1f をそのまま写す —— App アイコン ＋ 表示名 ＋
//  等幅のバージョン、白い薄膜に入れた出典表記、そして貢献フィードバックのカプセル。
//  審査上の理由から、打赏・赞助の類は一切置かない（このアプリ全体の方針）。
//

import SwiftUI

struct AboutSheet: View {

    @State private var safariItem: SafariItem?

    var body: some View {
        VStack(spacing: SheetMetrics.sectionSpacing) {
            appIcon
                .padding(.bottom, SheetMetrics.scaled(2))

            VStack(spacing: SheetMetrics.scaled(2)) {
                Text(Bundle.main.displayName ?? "Anitabi")
                    .font(SheetFont.titleLarge)
                    .foregroundStyle(Color.anitabiInk)
                if let version = Bundle.main.versionString {
                    Text("版本 \(version)")
                        .font(SheetFont.mono)
                        .foregroundStyle(Color.anitabiInkTertiary)
                }
            }

            // 設計稿 1f：白 50% の地・角丸 14・行間の広い 12px 本文（左寄せ）。
            Text("巡礼点数据来自 anitabi.cn 社区，按 CC BY-NC-SA 4.0 授权使用。截图与作品名版权归原权利方所有，仅用于场景对照。")
                .font(SheetFont.note)
                .foregroundStyle(Color.anitabiInkSecondary)
                .lineSpacing(SheetMetrics.noteLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scenePadding(.horizontal)
                .padding(.vertical, SheetMetrics.scaled(12))
                .anitabiPanel(radius: SheetMetrics.tileRadius)

            Button {
                safariItem = SafariItem(url: AnitabiWebLink.feedbackIssues)
            } label: {
                HStack(spacing: SheetMetrics.scaled(4)) {
                    Text("巡礼数据反馈")
                    Image(systemName: "arrow.up.right")
                        .font(SheetFont.meta)
                }
            }
            .buttonStyle(AnitabiCapsuleStyle(kind: .secondary, fullWidth: true))

            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .scenePadding(.horizontal)
        .padding(.top, SheetMetrics.topInset)
        .padding(.bottom, SheetMetrics.scrollBottomPadding)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
    }

    /// 設計稿 1f のアイコン砖は 76pt。角丸は iOS の squircle 比（0.2237）に合わせる。
    @ViewBuilder
    private var appIcon: some View {
        let side: CGFloat = 76
        if let icon = Bundle.main.appIcon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                .fill(Color.anitabiAccentFill)
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "mappin")
                        .font(.system(size: side * 0.42, weight: .semibold))
                        .foregroundStyle(Color.anitabiOnAccent)
                }
        }
    }
}
