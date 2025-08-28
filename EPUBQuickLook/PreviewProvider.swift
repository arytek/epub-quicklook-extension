//  PreviewProvider.swift
//  EPUBQuickLook

import AppKit
import WebKit
import QuickLookUI
import os.log

final class PreviewProvider: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private let log = OSLog(subsystem: "EPUBQuickLook", category: "Preview")

    // Build the view hierarchy with a WKWebView
    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.websiteDataStore = .nonPersistent()

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        wv.setValue(false, forKey: "drawsBackground")
        self.webView = wv

        let root = NSView()
        root.addSubview(wv)
        wv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            wv.topAnchor.constraint(equalTo: root.topAnchor),
            wv.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        self.view = root
    }

    // Quick Look entry point
    func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        os_log("preparePreviewOfFile called for %{public}@", log: log, type: .info, url.path)

        // ensure the view is loaded so `webView` exists
        _ = self.view

        // show immediate feedback
        let loading = """
        <html><body style="font: -apple-system-body; padding:24px">
        <p>Loading EPUB…</p>
        </body></html>
        """
        webView.loadHTMLString(loading, baseURL: nil)

        // stop Finder's spinner promptly
        DispatchQueue.main.async { completionHandler(nil) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            do {
                let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("EPUBQuickLook_\(UUID().uuidString)")

                let parser = EPUBParser()
                let extracted = try parser.unpackEPUB(at: url, to: workDir)
                let pkg = try parser.parsePackage(at: extracted)
                let merged = try parser.buildSingleHTML(from: pkg)

                let indexURL = extracted.appendingPathComponent("ql_index.html")
                try merged.html.write(to: indexURL, atomically: true, encoding: .utf8)

                DispatchQueue.main.async {
                    self?.webView.loadFileURL(indexURL, allowingReadAccessTo: extracted)
                    if #available(macOS 11.0, *) {
                        self?.preferredContentSize = NSSize(width: 900, height: 1100)
                    }
                }
            } catch {
                os_log("EPUB error: %{public}@", log: self?.log ?? .default, type: .error, error.localizedDescription)
                let html = """
                <html><body style="font: -apple-system-body; padding:24px">
                <h3>EPUB Quick Look Error</h3>
                <pre>\(error.localizedDescription)</pre>
                </body></html>
                """
                DispatchQueue.main.async {
                    self?.webView.loadHTMLString(html, baseURL: nil)
                }
            }
        }
    }
}
