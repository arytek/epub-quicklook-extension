//  PreviewProvider.swift
//  EPUBQuickLook
//
//  Quick Look preview controller that renders EPUBs in a scrollable WKWebView.

import AppKit
import WebKit
import QuickLookUI

final class PreviewProvider: NSViewController, QLPreviewingController {
    private var webView: WKWebView!

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true

        let wv = WKWebView(frame: .zero, configuration: cfg)
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

    // Quick Look entry point (completion-handler variant works across macOS versions)
    func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                // Use the shared EPUBParser (in EPUBParser.swift)
                let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("EPUBQuickLook_\(UUID().uuidString)")

                let parser = EPUBParser()
                let extracted = try parser.unpackEPUB(at: url, to: workDir)
                let pkg = try parser.parsePackage(at: extracted)
                let merged = try parser.buildSingleHTML(from: pkg)

                DispatchQueue.main.async {
                    self?.webView.loadHTMLString(merged.html, baseURL: merged.baseURL)
                    if #available(macOS 11.0, *) { self?.preferredContentSize = NSSize(width: 900, height: 1100) }
                    completionHandler(nil)
                }
            } catch {
                DispatchQueue.main.async { completionHandler(error) }
            }
        }
    }
}
