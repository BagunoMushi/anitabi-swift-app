//
//  EtiquetteSheet.swift
//  anitabi
//
//  巡礼マナーの注意（`ScenePoint.needsEtiquetteWarning` が立つ地標＝学校・図書館など）。
//  Web 版の ⚠️ アイコンは GitHub issue へ直リンクしているだけだが、アプリでは
//  「まず現場での振る舞いを 3 文で伝えて、詳細は Safari へ」という 2 段にする。
//
//  「了解更多」の SFSafariViewController は**この sheet 自身**から出す。親（地標カード）へ
//  投げ返して閉じてから開く形にすると、同フレームの dismiss + present で後の呈现が落ちる。
//

import SwiftUI

struct EtiquetteSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var safariItem: SafariItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("注意巡礼礼仪")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text("这里是学校、图书馆一类的场所，请不要打扰在校师生和馆内秩序。拍摄请在校外或对外开放的区域进行，不要进入私人领域。请保持安静、遵守当地规定与现场指引，把巡礼留在不打扰任何人的范围里。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // 高さは `controlSize(.large)`（実測 50pt）に決めさせる —— frame(height:) は書かない。
            // 幅だけ全幅に伸ばす。prominent は 1 画面 1 枚まで（「知道了」だけ）。
            VStack(spacing: 10) {
                Button {
                    safariItem = SafariItem(url: AnitabiWebLink.etiquetteIssue)
                } label: {
                    Text("了解更多").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    dismiss()
                } label: {
                    Text("知道了").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, SheetMetrics.horizontalPadding)
        .padding(.vertical, 20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
    }
}
