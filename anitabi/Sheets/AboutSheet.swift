//
//  AboutSheet.swift
//  anitabi
//
//  HomeSheet「⋯」メニューの「关于」。App アイコン＋表示名＋バージョン、データの出典表記、
//  そして貢献フィードバック用の GitHub issue へのリンクだけの、素っ気ない 1 枚。
//  審査上の理由から、打赏・赞助の類は一切置かない（このアプリ全体の方針）。
//

import SwiftUI

struct AboutSheet: View {

    @State private var safariItem: SafariItem?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                appIcon
                VStack(spacing: 2) {
                    Text(Bundle.main.displayName ?? "Anitabi")
                        .font(.title3.weight(.semibold))
                    if let version = Bundle.main.versionString {
                        Text("版本 \(version)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("数据由 anitabi.cn 社区贡献 · CC BY-NC-SA 4.0")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    safariItem = SafariItem(url: AnitabiWebLink.feedbackIssues)
                } label: {
                    Text("巡礼数据反馈")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SheetMetrics.horizontalPadding)
        .padding(.top, SheetMetrics.topInset)
        .padding(.bottom, 24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = Bundle.main.appIcon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 64 * 0.2237, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 64 * 0.2237, style: .continuous)
                .fill(Color.accentColor.gradient)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "app.fill")
                        .font(.system(size: 64 * 0.4))
                        .foregroundStyle(.white)
                }
        }
    }
}
