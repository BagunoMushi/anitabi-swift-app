//
//  EtiquetteSheet.swift
//  anitabi
//
//  巡礼マナーの注意（`ScenePoint.needsEtiquetteWarning` が立つ地標＝学校・図書館など）。設計稿 1g。
//  「了解更多」の SFSafariViewController は**この sheet 自身**から出す —— 親へ投げ返して閉じてから
//  開く形にすると、同フレームの dismiss + present で後の呈现が落ちる。
//

import SwiftUI

struct EtiquetteSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var safariItem: SafariItem?

    var body: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.headerBottomSpacing) {
            HStack(spacing: SheetMetrics.thumbnailGap) {
                Text(verbatim: "!")
                    .font(SheetFont.titleCompactWork)
                    .foregroundStyle(.white)
                    .frame(width: SheetMetrics.guidanceIconDiameter, height: SheetMetrics.guidanceIconDiameter)
                    .background(Color.anitabiWarnIcon, in: .circle)
                Text("巡礼礼仪")
                    .font(SheetFont.titleLarge)
                    .foregroundStyle(Color.anitabiInk)
            }

            Text("这里是学校、图书馆一类的场所，请不要打扰在校师生和馆内秩序。拍摄请在校外或对外开放的区域进行，不要进入私人领域。请保持安静、遵守当地规定与现场指引，把巡礼留在不打扰任何人的范围里。")
                .font(SheetFont.note)
                .foregroundStyle(Color.anitabiInkSecondary)
                .lineSpacing(SheetMetrics.etiquetteLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SheetMetrics.scaled(16))
                .padding(.vertical, SheetMetrics.scaled(14))
                .anitabiPanel(radius: SheetMetrics.tileRadius)

            Spacer(minLength: 0)

            HStack(spacing: SheetMetrics.itemSpacing) {
                Button {
                    safariItem = SafariItem(url: AnitabiWebLink.etiquetteIssue)
                } label: {
                    HStack(spacing: SheetMetrics.scaled(4)) {
                        Text("了解更多")
                        Image(systemName: "arrow.up.right")
                            .font(SheetFont.meta)
                    }
                }
                .buttonStyle(AnitabiCapsuleStyle(kind: .secondary, fullWidth: true))

                Button("知道了") { dismiss() }
                    .buttonStyle(AnitabiCapsuleStyle(kind: .primary, fullWidth: true))
            }
        }
        .scenePadding(.horizontal)
        .padding(.top, SheetMetrics.topInset)
        .padding(.bottom, SheetMetrics.scaled(20))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
    }
}
