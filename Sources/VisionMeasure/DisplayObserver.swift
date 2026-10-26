import SwiftUI
import RefractionCore

#if os(iOS)
import UIKit

struct DisplayObserver: UIViewRepresentable {
    var refreshToken = 0
    let onChange: (DisplayContext?) -> Void
    func makeUIView(context: Context) -> DisplayObservationView { DisplayObservationView() }
    func updateUIView(_ view: DisplayObservationView, context: Context) {
        view.onChange = onChange
        view.reportContext()
    }
}
final class DisplayObservationView: UIView {
    var onChange: ((DisplayContext?) -> Void)?
    private var previous: DisplayContext?
    override func didMoveToWindow() { super.didMoveToWindow(); reportContext() }
    override func layoutSubviews() { super.layoutSubviews(); reportContext() }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection); reportContext()
    }
    func reportContext() {
        guard let window=window,let scene=window.windowScene else { return }
        let screen=scene.screen
        let orientation: UIInterfaceOrientation
        if #available(iOS 26.0, *) { orientation=scene.effectiveGeometry.interfaceOrientation }
        else { orientation=scene.interfaceOrientation }
        let value = DisplayContext(displayID:"scene:"+scene.session.persistentIdentifier,
            widthPoints:window.bounds.width,heightPoints:window.bounds.height,
            scale:window.traitCollection.displayScale,
            nativeWidthPixels:screen.nativeBounds.width,nativeHeightPixels:screen.nativeBounds.height,
            physicalOrientation:UIDevice.current.orientation.rawValue,interfaceOrientation:orientation.rawValue)
        guard value.isUsable, value != previous else { return }
        previous = value
        DispatchQueue.main.async { [weak self] in
            guard self?.previous == value else { return }
            self?.onChange?(value)
        }
    }
}
#else
import AppKit

struct DisplayObserver: NSViewRepresentable {
    var refreshToken = 0
    let onChange: (DisplayContext?) -> Void
    func makeNSView(context: Context) -> DisplayObservationView { DisplayObservationView() }
    func updateNSView(_ view: DisplayObservationView, context: Context) { view.onChange = onChange; view.reportContext() }
}
final class DisplayObservationView: NSView {
    var onChange: ((DisplayContext?) -> Void)?
    private var previous: DisplayContext?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); reportContext() }
    override func layout() { super.layout(); reportContext() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); reportContext() }
    func reportContext() {
        guard let window=window,let screen=window.screen else { return }
        let value = DisplayContext(displayID:String(describing:screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "unknown"),
            widthPoints:window.contentLayoutRect.width,heightPoints:window.contentLayoutRect.height,
            scale:window.backingScaleFactor,
            nativeWidthPixels:screen.frame.width*screen.backingScaleFactor,
            nativeHeightPixels:screen.frame.height*screen.backingScaleFactor)
        guard value.isUsable, value != previous else { return }
        previous = value
        DispatchQueue.main.async { [weak self] in
            guard self?.previous == value else { return }
            self?.onChange?(value)
        }
    }
}
#endif
