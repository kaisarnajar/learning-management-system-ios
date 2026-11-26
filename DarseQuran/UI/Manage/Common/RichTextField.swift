import Observation
import SwiftUI
import WebKit

/*
 * The rich text editor of the admin forms (Android's RichTextField in Forms.kt, which uses compose-richeditor).
 * Here the editing surface is a content-editable web view, which reads and writes HTML natively: what the website's
 * editor stores is what this one loads and sends back.
 */

/// Rich text, edited as on the website (bold, italic, underline, strike, heading, lists, links, alignment) and
/// read/written as HTML. [initialHtml] is loaded once; every edit reports the new HTML through [onChange].
struct RichTextField: View {
    let label: String
    let initialHtml: String
    let onChange: (String) -> Void
    var minHeight: CGFloat = 220
    @State private var editor = RichTextEditor()
    @State private var linkDialog = false
    @Environment(\.colorScheme) private var colorScheme

    init(_ label: String, initialHtml: String, minHeight: CGFloat = 220, onChange: @escaping (String) -> Void) {
        self.label = label
        self.initialHtml = initialHtml
        self.minHeight = minHeight
        self.onChange = onChange
    }

    var body: some View {
        let s = editor.state
        VStack(alignment: .leading, spacing: 6) {
            Text(label).textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurfaceVariant)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ToolButton(.formatBold, "Bold", s.bold) { editor.command("bold") }
                    ToolButton(.formatItalic, "Italic", s.italic) { editor.command("italic") }
                    ToolButton(.formatUnderlined, "Underline", s.underline) { editor.command("underline") }
                    ToolButton(.formatStrikethrough, "Strikethrough", s.strike) { editor.command("strikeThrough") }
                    ToolButton(.formatTitle, "Heading", s.heading) { editor.call("heading()") }
                    ToolButton(.formatListBulleted, "Bulleted list", s.bulleted) { editor.command("insertUnorderedList") }
                    ToolButton(.formatListNumbered, "Numbered list", s.numbered) { editor.command("insertOrderedList") }
                    ToolButton(.formatAlignLeft, "Align left", s.alignLeft) { editor.command("justifyLeft") }
                    ToolButton(.formatAlignCenter, "Centre", s.alignCenter) { editor.command("justifyCenter") }
                    ToolButton(.formatAlignRight, "Align right", s.alignRight) { editor.command("justifyRight") }
                    if s.link {
                        ToolButton(.linkOff, "Remove link", true) { editor.call("removeLink()") }
                    } else {
                        ToolButton(.link, "Link", false) { linkDialog = true }
                    }
                }
                .padding(.horizontal, 4)
            }
            .background(Scheme.surfaceContainer, in: RoundedRectangle(cornerRadius: Radius.input))
            RichTextWebView(editor: editor, initialHtml: initialHtml, colors: EditorColors(colorScheme), onChange: onChange)
                .frame(height: max(minHeight, editor.contentHeight))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .strokeBorder(s.focused ? Scheme.primary : Scheme.outline, lineWidth: s.focused ? 2 : 1)
                        .allowsHitTesting(false)
                )
                .accessibilityLabel(label)
        }
        .textInputDialog(
            isPresented: $linkDialog, title: "Add a link", label: "https://…", confirmLabel: "Add", required: true,
            message: "Select the words to link first, or the address is added as the link text.", singleLine: true
        ) { url in
            editor.addLink(url.hasPrefix("http") ? url : "https://\(url)")
        }
    }
}

/// A toolbar toggle: 40pt, primary when on.
private struct ToolButton: View {
    let icon: Icon
    let label: String
    let active: Bool
    let action: () -> Void

    init(_ icon: Icon, _ label: String, _ active: Bool, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            icon.image.font(.system(size: 17, weight: .medium))
                .foregroundStyle(active ? Scheme.primary : Scheme.onSurfaceVariant)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(shape: Circle()))
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }
}

/// What the cursor is on, as the toolbar shows it.
struct RichTextState: Equatable {
    var bold = false, italic = false, underline = false, strike = false, heading = false
    var bulleted = false, numbered = false
    var alignLeft = false, alignCenter = false, alignRight = false
    var link = false
    var focused = false
}

/// Talks to the editor's web view: runs formatting commands and keeps the toolbar state and the content height.
@MainActor
@Observable
final class RichTextEditor {
    var state = RichTextState()
    var contentHeight: CGFloat = 0
    @ObservationIgnored weak var webView: WKWebView?

    /// A document.execCommand without a value ("bold", "insertUnorderedList", …).
    func command(_ name: String) { call("cmd(\(jsString(name)))") }

    func addLink(_ href: String) { call("addLink(\(jsString(href)))") }

    func call(_ js: String) { webView?.evaluateJavaScript(js, completionHandler: nil) }
}

/// A JavaScript string literal for [value].
private func jsString(_ value: String) -> String {
    let data = (try? JSONEncoder().encode([value])) ?? Data("[\"\"]".utf8)
    let array = String(decoding: data, as: UTF8.self)
    return String(array.dropFirst().dropLast())
}

/// The editor's colours for the current appearance, as CSS.
struct EditorColors: Equatable {
    let text: String
    let link: String
    let caret: String

    init(_ scheme: ColorScheme) {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        text = cssColor(UIColor(Scheme.onSurface).resolvedColor(with: traits))
        link = cssColor(UIColor(Scheme.primary).resolvedColor(with: traits))
        caret = link
    }
}

private func cssColor(_ color: UIColor) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return "rgba(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)),\(a))"
}

private struct RichTextWebView: UIViewRepresentable {
    let editor: RichTextEditor
    let initialHtml: String
    let colors: EditorColors
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor, initialHtml: initialHtml, onChange: onChange) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakHandler(context.coordinator), name: "rt")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = context.coordinator
        editor.webView = web
        context.coordinator.colors = colors
        web.loadHTMLString(editorPage(colors), baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onChange = onChange
        if context.coordinator.colors != colors {
            context.coordinator.colors = colors
            web.evaluateJavaScript("setColors(\(jsString(colors.text)), \(jsString(colors.link)))", completionHandler: nil)
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "rt")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let editor: RichTextEditor
        let initialHtml: String
        var onChange: (String) -> Void
        var colors: EditorColors?
        private var loaded = false

        init(editor: RichTextEditor, initialHtml: String, onChange: @escaping (String) -> Void) {
            self.editor = editor
            self.initialHtml = initialHtml
            self.onChange = onChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !loaded else { return }
            loaded = true
            // The HTML is loaded once; edits come back through "html" messages.
            webView.evaluateJavaScript("setHtml(\(jsString(initialHtml)))", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            // Only the editor page itself loads; tapping a link in the text must not navigate away.
            decisionHandler(action.navigationType == .other && !loaded ? .allow : .cancel)
        }

        func receive(_ body: Any) {
            guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
            switch type {
            case "html":
                if let html = message["html"] as? String { onChange(html) }
            case "height":
                if let h = message["height"] as? Double { editor.contentHeight = CGFloat(h) }
            case "state":
                func flag(_ key: String) -> Bool { (message[key] as? Bool) ?? false }
                editor.state = RichTextState(
                    bold: flag("bold"), italic: flag("italic"), underline: flag("underline"), strike: flag("strike"), heading: flag("heading"),
                    bulleted: flag("ul"), numbered: flag("ol"), alignLeft: flag("left"), alignCenter: flag("center"), alignRight: flag("right"),
                    link: flag("link"), focused: flag("focused")
                )
            default: break
            }
        }
    }

    /// Holds the coordinator weakly (the content controller keeps its handlers strongly).
    final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: Coordinator?
        init(_ target: Coordinator) { self.target = target }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            MainActor.assumeIsolated { target?.receive(message.body) }
        }
    }
}

/// The editor page: one content-editable element and the commands the toolbar calls.
private func editorPage(_ colors: EditorColors) -> String {
    """
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
    <style>
    :root { --text: \(colors.text); --link: \(colors.link); }
    html, body { margin: 0; padding: 0; height: 100%; background: transparent; -webkit-text-size-adjust: 100%; }
    #ed { outline: none; padding: 16px; color: var(--text); caret-color: var(--link);
          font: 15px/24px 'Poppins', -apple-system, sans-serif; letter-spacing: 0.5px; word-wrap: break-word; }
    #ed a { color: var(--link); }
    #ed h1, #ed h2, #ed h3 { font-size: 22px; line-height: 30px; font-weight: 700; margin: 8px 0; }
    #ed p { margin: 0 0 8px 0; }
    #ed ul, #ed ol { padding-left: 24px; margin: 0 0 8px 0; }
    </style></head><body>
    <div id="ed" contenteditable="true"></div>
    <script>
    const ed = document.getElementById('ed');
    let saved = null;
    const send = (m) => window.webkit.messageHandlers.rt.postMessage(m);
    function post() { send({ type: 'html', html: ed.innerHTML }); }
    function height() { send({ type: 'height', height: Math.ceil(ed.getBoundingClientRect().height) }); }
    function inside(node) { while (node) { if (node === ed) return true; node = node.parentNode; } return false; }
    function linkAt(node) { while (node && node !== ed) { if (node.nodeName === 'A') return node; node = node.parentNode; } return null; }
    function state() {
      const s = window.getSelection();
      const here = s.rangeCount > 0 && inside(s.anchorNode);
      const q = (c) => here && document.queryCommandState(c);
      const block = here ? String(document.queryCommandValue('formatBlock') || '') : '';
      send({ type: 'state', bold: q('bold'), italic: q('italic'), underline: q('underline'), strike: q('strikeThrough'),
             heading: /^h[1-6]$/i.test(block), ul: q('insertUnorderedList'), ol: q('insertOrderedList'),
             left: q('justifyLeft'), center: q('justifyCenter'), right: q('justifyRight'),
             link: here && linkAt(s.anchorNode) !== null, focused: document.activeElement === ed });
    }
    function restore() {
      ed.focus();
      if (saved) { const s = window.getSelection(); s.removeAllRanges(); s.addRange(saved); }
    }
    function changed() { post(); height(); state(); }
    function cmd(name) { restore(); document.execCommand(name, false, null); changed(); }
    function heading() {
      restore();
      const block = String(document.queryCommandValue('formatBlock') || '');
      document.execCommand('formatBlock', false, /^h[1-6]$/i.test(block) ? 'p' : 'h2');
      changed();
    }
    function esc(t) { return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
    function addLink(href) {
      restore();
      const s = window.getSelection();
      if (s.isCollapsed) document.execCommand('insertHTML', false, '<a href="' + esc(href) + '">' + esc(href) + '</a>');
      else document.execCommand('createLink', false, href);
      changed();
    }
    function removeLink() {
      restore();
      const s = window.getSelection();
      const a = linkAt(s.anchorNode);
      if (a && s.isCollapsed) { const r = document.createRange(); r.selectNodeContents(a); s.removeAllRanges(); s.addRange(r); }
      document.execCommand('unlink', false, null);
      changed();
    }
    function setHtml(html) { ed.innerHTML = html; height(); }
    function setColors(text, link) {
      document.documentElement.style.setProperty('--text', text);
      document.documentElement.style.setProperty('--link', link);
    }
    document.addEventListener('selectionchange', () => {
      const s = window.getSelection();
      if (s.rangeCount > 0 && inside(s.anchorNode)) saved = s.getRangeAt(0).cloneRange();
      state();
    });
    ed.addEventListener('input', changed);
    // A tap below the text (the field is at least 220pt tall) puts the cursor at the end.
    document.body.addEventListener('click', (e) => {
      if (e.target !== document.body) return;
      ed.focus();
      const r = document.createRange(); r.selectNodeContents(ed); r.collapse(false);
      const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
    });
    ed.addEventListener('focus', state);
    ed.addEventListener('blur', state);
    new ResizeObserver(height).observe(ed);
    </script></body></html>
    """
}
