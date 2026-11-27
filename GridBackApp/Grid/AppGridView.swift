import AppKit
import GridBackCore
import QuartzCore
import SwiftUI

struct AppGridView: View {
    @ObservedObject var model: GridBackModel
    var layout: LaunchGridLayout
    var items: [GridBackCore.GridItem]
    var hiddenID: String?
    var hiddenFolderID: String?
    var armedID: String?
    var blockLaunch: Bool
    var displayFolders: [AppFolder]? = nil
    var suppressedAppID: String? = nil
    @Environment(\.ink) private var ink

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if hiddenID == nil {
                        if model.openFolderID != nil {
                            model.requestCloseFolder()
                        } else {
                            model.hideOverlay()
                        }
                    }
                }
            ForEach(Array(items.enumerated()), id: \.element.id) { slot, item in
                if item.id != hiddenID && item.id != hiddenFolderID {
                    tile(item, slot: slot)
                        .position(
                            x: layout.originX + layout.columnCenter(slot),
                            y: layout.rowCenter(slot)
                        )
                }
            }
        }
        .frame(width: layout.pageWidth, height: layout.gridHeight)
        .animation(.easeInOut(duration: GridReorderMotion.displacedDuration), value: items)
    }

    @ViewBuilder
    private func tile(_ item: GridBackCore.GridItem, slot: Int) -> some View {
        let armed = item.id == armedID
        switch item {
        case .app(let id):
            AppIconButton(
                title: model.appsByID[id]?.displayName ?? id,
                image: model.iconImages[id],
                iconSide: layout.iconSide,
                labelWidth: max(layout.hitWidth - 12, layout.iconSide)
            ) {
                guard !blockLaunch else { return }
                model.launch(id: id)
            }
            .overlay {
                if armed {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(ink.dropRing.color, lineWidth: 3)
                        .frame(width: layout.iconSide + 14, height: layout.iconSide + 14)
                        .offset(y: -(layout.labelHeight + layout.iconLabelGap) / 2)
                }
            }
        case .folder(let id):
            let folder = (displayFolders ?? model.layout.folders).first { $0.id == id } ?? model.layout.folder(id)
            FolderTile(
                name: folder?.name ?? AppFolder.defaultName,
                icons: (folder?.appIDs ?? []).filter { $0 != suppressedAppID }.prefix(9).map { model.iconImages[$0] },
                iconSide: layout.iconSide,
                labelWidth: max(layout.hitWidth - 12, layout.iconSide),
                armed: armed
            ) {
                guard !blockLaunch else { return }
                model.openFolder(id)
            }
        }
    }
}

struct FolderTile: View {
    let name: String
    let icons: [NSImage?]
    var iconSide: CGFloat
    var labelWidth: CGFloat
    var armed: Bool
    let action: () -> Void
    @Environment(\.ink) private var ink

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                folderIcon
                    .frame(width: iconSide, height: iconSide)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink.label.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: labelWidth)
                    .gridTextShadow(ink.labelShadow)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(GridPlainButtonStyle())
        .fixedSize()
        .help(name)
        .accessibilityLabel(name)
    }

    private var folderIcon: some View {
        let mini = iconSide / 3.6
        return RoundedRectangle(cornerRadius: iconSide * 0.22, style: .continuous)
            .fill(ink.folderFill(armed: armed).color)
            .overlay {
                RoundedRectangle(cornerRadius: iconSide * 0.22, style: .continuous)
                    .strokeBorder(ink.folderStroke(armed: armed).color, lineWidth: armed ? 3 : 1)
            }
            .overlay {
                LazyVGrid(columns: Array(repeating: SwiftUI.GridItem(.fixed(mini), spacing: 3), count: 3), spacing: 3) {
                    ForEach(0..<9, id: \.self) { index in
                        miniIcon(index < icons.count ? icons[index] : nil, side: mini)
                    }
                }
                .padding(iconSide * 0.12)
            }
    }

    private func miniIcon(_ image: NSImage?, side: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: side, height: side)
    }
}

struct SearchPill: View {
    @Binding var query: String
    @FocusState var isFocused: Bool
    @Environment(\.ink) private var ink

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ink.muted.color)
            SearchPillField(text: $query, isFocused: $isFocused)
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 18)
        .frame(width: 280, height: 40)
        .background(ink.searchPill.color, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
        .accessibilityLabel(String(localized: "Search"))
        .accessibilityValue(query)
    }
}

/// The system text field draws its placeholder in dark grey and its caret in
/// the accent blue. This field paints both from the ink instead.
private struct SearchPillField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    @Environment(\.ink) private var ink

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused)
    }

    func makeNSView(context: Context) -> SearchPillTextField {
        let field = SearchPillTextField(string: "")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = SearchPillTextField.font
        field.apply(ink)
        field.delegate = context.coordinator
        field.setAccessibilityLabel(String(localized: "Search"))
        return field
    }

    func updateNSView(_ field: SearchPillTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        if field.stringValue != text {
            context.coordinator.isUpdatingFromModel = true
            field.stringValue = text
            context.coordinator.isUpdatingFromModel = false
        }
        field.apply(ink)
        guard isFocused.wrappedValue, let window = field.window else { return }
        let editor = field.currentEditor()
        guard window.firstResponder !== field, window.firstResponder !== editor else { return }
        DispatchQueue.main.async {
            guard field.window?.firstResponder !== field,
                  field.window?.firstResponder !== field.currentEditor() else { return }
            field.window?.makeFirstResponder(field)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isFocused: FocusState<Bool>.Binding
        var isUpdatingFromModel = false

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding) {
            self.text = text
            self.isFocused = isFocused
        }

        /// Undo and redo post this as well, so the query follows the field.
        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdatingFromModel, let field = notification.object as? NSTextField else { return }
            let cleaned = SearchQueryText.cleaned(field.stringValue)
            if cleaned != field.stringValue {
                write(cleaned, into: field)
            }
            if text.wrappedValue != cleaned {
                text.wrappedValue = cleaned
            }
            (field as? SearchPillTextField)?.paintCaret()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            shouldChangeTextIn range: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isUpdatingFromModel, let replacementString else { return true }
            let current = textView.string as NSString
            guard range.location != NSNotFound, NSMaxRange(range) <= current.length else { return true }
            let proposed = current.replacingCharacters(in: range, with: replacementString)
            let cleaned = SearchQueryText.cleaned(proposed)
            guard cleaned != proposed else { return true }

            let fragment = SearchQueryText.cleaned(replacementString)
            let fragmentFits = current.replacingCharacters(in: range, with: fragment) == cleaned
            let expected = textView.string
            DispatchQueue.main.async { [weak textView] in
                guard let textView, textView.string == expected else { return }
                if fragmentFits {
                    textView.insertText(fragment, replacementRange: range)
                    return
                }
                let whole = NSRange(location: 0, length: (textView.string as NSString).length)
                guard textView.shouldChangeText(in: whole, replacementString: cleaned) else { return }
                textView.replaceCharacters(in: whole, with: cleaned)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: (cleaned as NSString).length, length: 0))
            }
            return false
        }

        /// A change that skipped `shouldChangeTextIn` still has to land as one short line.
        /// Undo registration stays off so this rewrite is not a second undo step.
        private func write(_ cleaned: String, into field: NSTextField) {
            isUpdatingFromModel = true
            defer { isUpdatingFromModel = false }
            guard let editor = field.currentEditor() else {
                field.stringValue = cleaned
                return
            }
            let undo = editor.undoManager
            undo?.disableUndoRegistration()
            editor.string = cleaned
            editor.selectedRange = NSRange(location: (cleaned as NSString).length, length: 0)
            undo?.enableUndoRegistration()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
            (notification.object as? SearchPillTextField)?.paintCaret()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if field.window?.firstResponder !== field.currentEditor() {
                isFocused.wrappedValue = false
            }
        }
    }
}

private final class SearchPillTextField: NSTextField {
    static let font = NSFont.systemFont(ofSize: 16, weight: .medium)

    private var caretNSColor: NSColor?
    private var appliedInk: Ink?
    private var shownText: NSColor?
    private var shownCaret: NSColor?
    private var shownPlaceholder: NSColor?
    private var inkTimer: Timer?

    static func placeholder(_ color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: String(localized: "Search"),
            attributes: [
                .foregroundColor: color,
                .font: font
            ]
        )
    }

    override var allowsVibrancy: Bool { false }

    deinit {
        inkTimer?.invalidate()
    }

    func apply(_ ink: Ink) {
        if ink != appliedInk {
            let previous = appliedInk
            appliedInk = ink
            if let previous, shouldAnimateInk {
                startInkAnimation(from: previous, to: ink)
            } else {
                stopInkAnimation()
                show(ink)
            }
        }
        paintCaret()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        paintCaret()
        DispatchQueue.main.async { [weak self] in paintCaret() }
        return accepted
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The window appearance flips with the ink. Re-apply the colours we
        // paint so the field does not pick up the system label colour for a frame.
        reapplyShownColors()
        DispatchQueue.main.async { [weak self] in self?.reapplyShownColors() }
    }

    func paintCaret() {
        guard let editor = currentEditor() as? NSTextView, let caretNSColor else { return }
        editor.insertionPointColor = caretNSColor
        editor.textColor = textColor
        guard let textColor else { return }
        var attributes = editor.selectedTextAttributes
        attributes[.foregroundColor] = textColor
        editor.selectedTextAttributes = attributes
    }

    private var shouldAnimateInk: Bool {
        window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func show(_ ink: Ink) {
        applyShown(
            text: ink.searchText.nsColor,
            caret: ink.searchCaret.nsColor,
            placeholder: ink.searchPlaceholder.nsColor
        )
    }

    private func applyShown(text: NSColor, caret: NSColor, placeholder: NSColor) {
        shownText = text
        shownCaret = caret
        shownPlaceholder = placeholder
        textColor = text
        caretNSColor = caret
        placeholderAttributedString = Self.placeholder(placeholder)
        paintCaret()
    }

    private func reapplyShownColors() {
        guard let shownText, let shownCaret, let shownPlaceholder else { return }
        textColor = shownText
        caretNSColor = shownCaret
        placeholderAttributedString = Self.placeholder(shownPlaceholder)
        paintCaret()
    }

    private func stopInkAnimation() {
        inkTimer?.invalidate()
        inkTimer = nil
    }

    /// Moves the field's own colours with the backdrop crossfade. The field is
    /// not a SwiftUI colour, so it would otherwise jump to the new ink at once.
    private func startInkAnimation(from: Ink, to: Ink) {
        let startText = shownText ?? from.searchText.nsColor
        let startCaret = shownCaret ?? from.searchCaret.nsColor
        let startPlaceholder = shownPlaceholder ?? from.searchPlaceholder.nsColor
        let endText = to.searchText.nsColor
        let endCaret = to.searchCaret.nsColor
        let endPlaceholder = to.searchPlaceholder.nsColor
        let started = CACurrentMediaTime()
        stopInkAnimation()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let raw = min(1, (CACurrentMediaTime() - started) / InkCrossfade.duration)
            let t = Self.easeInOut(raw)
            self.applyShown(
                text: Self.mix(startText, endText, t),
                caret: Self.mix(startCaret, endCaret, t),
                placeholder: Self.mix(startPlaceholder, endPlaceholder, t)
            )
            if raw >= 1 {
                timer.invalidate()
                if let current = self.inkTimer, current === timer {
                    self.inkTimer = nil
                }
            }
        }
        inkTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Same curve as the backdrop dissolve (`easeInEaseOut`: 0.42, 0, 0.58, 1).
    private static func easeInOut(_ x: Double) -> CGFloat {
        let target = min(max(x, 0), 1)
        var lo = 0.0
        var hi = 1.0
        var t = target
        for _ in 0..<16 {
            let sample = unitBezier(t, 0.42, 0.58)
            if abs(sample - target) < 0.000_1 { break }
            if sample < target {
                lo = t
            } else {
                hi = t
            }
            t = (lo + hi) / 2
        }
        return CGFloat(unitBezier(t, 0, 1))
    }

    private static func unitBezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return (3 * u * u * t * p1) + (3 * u * t * t * p2) + (t * t * t)
    }

    private static func mix(_ from: NSColor, _ to: NSColor, _ amount: CGFloat) -> NSColor {
        guard let start = from.usingColorSpace(.sRGB), let end = to.usingColorSpace(.sRGB) else {
            return amount >= 1 ? to : from
        }
        return NSColor(
            srgbRed: start.redComponent + (end.redComponent - start.redComponent) * amount,
            green: start.greenComponent + (end.greenComponent - start.greenComponent) * amount,
            blue: start.blueComponent + (end.blueComponent - start.blueComponent) * amount,
            alpha: start.alphaComponent + (end.alphaComponent - start.alphaComponent) * amount
        )
    }
}
