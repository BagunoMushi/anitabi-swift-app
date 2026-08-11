//
//  SheetShapeReader.swift
//  anitabi
//
//  sheet の**実際に描かれているカード**の枠を UIKit 側から実測して SwiftUI へ返す。iOS 26 の
//  浮き sheet は中身の枠と可視カードの枠が一致せず、その差は系统の API では取れないので、
//  `presentationController.presentedView` を辿って毎回実測する（private API なし）。
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
