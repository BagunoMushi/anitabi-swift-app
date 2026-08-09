//
//  SheetShapeReader.swift
//  anitabi
//
//  sheet の**実際に描かれているカード**の枠を UIKit 側から実測して SwiftUI へ返す。
//
//  なぜ要るか：iOS 26 の浮き sheet（特に小さい档の「迷你条」）は、SwiftUI の中身の枠と
//  可視カードの枠が一致しない。中身は枠いっぱいに配られるのに、カードはその内側に描かれる。
//  この差は系统の API では取れない（`safeAreaInsets` は上下とも 0 を返す。実測）。
//  定数で埋めると機種・OS 更新で必ずずれるので、UIKit の view 階層から
//  `presentationController.presentedView` を辿って**毎回実測**する。
//
//  やっていることは SwiftUI-Introspect / SheeKit と同じ「呈现側の UIKit を覗く」だけで、
//  private API には触れていない。
//

import SwiftUI
import UIKit

struct SheetShapeReader: UIViewRepresentable {

    /// 可視カードの枠（グローバル座標）。取れないときは nil。
    let onChange: (CGRect?) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
        uiView.report()
    }

    final class ProbeView: UIView {
        var onChange: ((CGRect?) -> Void)?
        private var last: CGRect?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        /// 呈现側の view を responder chain から辿って、その枠を報せる。
        /// 拖动の途中も `layoutSubviews` で毎フレーム来るので、1pt 未満の揺れは捨てる。
        func report() {
            let frame = presentedFrame()
            if let last, let frame, abs(last.minY - frame.minY) < 1, abs(last.height - frame.height) < 1 {
                return
            }
            last = frame
            onChange?(frame)
        }

        private func presentedFrame() -> CGRect? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   let presented = controller.presentationController?.presentedView {
                    return presented.convert(presented.bounds, to: nil)
                }
                responder = current.next
            }
            return nil
        }
    }
}
