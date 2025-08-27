//
//  EPUBParser.swift
//  EPUBQuickLook
//
//  Created by Aryan on 27/8/2025.
//

import Foundation
import ZIPFoundation

struct EPUBPackage {
    let rootFolder: URL      // folder where OPF lives
    let spineURLs: [URL]     // ordered list of xhtml/html files
}

enum EPUBParseError: Error { case containerNotFound, opfNotFound, malformed, io }

final class EPUBParser: NSObject {
    func unpackEPUB(at epubURL: URL, to workDir: URL) throws -> URL {
        // Using ZIPFoundation’s FileManager.unzipItem
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: epubURL, to: workDir)
        return workDir
    }

    func parsePackage(at extractedRoot: URL) throws -> EPUBPackage {
        // 1) Locate container.xml
        let containerURL = extractedRoot.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else { throw EPUBParseError.containerNotFound }
        let containerData = try Data(contentsOf: containerURL)
        let container = try XMLDocument(data: containerData)
        // Find the @full-path attribute on the <rootfile> element (ignore namespaces)
        let rootfileNodes = try container.nodes(forXPath: "//*[local-name()='rootfile']/@full-path")
        guard let rootAttr = rootfileNodes.first as? XMLNode,
              let opfPath = rootAttr.stringValue else {
            throw EPUBParseError.opfNotFound
        }
        let opfURL = extractedRoot.appendingPathComponent(opfPath)
        let rootFolder = opfURL.deletingLastPathComponent()

        // 2) Parse OPF: manifest + spine
        let opfData = try Data(contentsOf: opfURL)
        let opf = try XMLDocument(data: opfData)

        // manifest: id -> href
        var hrefByID: [String: String] = [:]
        let itemNodes = (try opf.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")) as? [XMLElement] ?? []
        for item in itemNodes {
            if let id = item.attribute(forName: "id")?.stringValue,
               let href = item.attribute(forName: "href")?.stringValue {
                hrefByID[id] = href
            }
        }

        // spine order
        var spineHrefs: [String] = []
        let spineNodes = (try opf.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']")) as? [XMLElement] ?? []
        for node in spineNodes {
            if let ref = node.attribute(forName: "idref")?.stringValue,
               let href = hrefByID[ref] {
                spineHrefs.append(href)
            }
        }

        let spineURLs: [URL] = spineHrefs.compactMap { href in
            let u = URL(fileURLWithPath: href, relativeTo: rootFolder)
            let ext = u.pathExtension.lowercased()
            return ["xhtml","html","htm"].contains(ext) ? u : nil
        }

        guard !spineURLs.isEmpty else { throw EPUBParseError.malformed }
        return EPUBPackage(rootFolder: rootFolder, spineURLs: spineURLs)
    }

    func buildSingleHTML(from pkg: EPUBPackage) throws -> (html: String, baseURL: URL) {
        // Merge chapter bodies into one scrollable page.
        var body = ""
        let base = pkg.rootFolder
        for (i, url) in pkg.spineURLs.enumerated() {
            let src = try String(contentsOf: url, encoding: .utf8)
            let extracted = Self.extractBody(html: src)
            body += "\n<section class=\"chapter\" id=\"ch\(i)\">\n" + Self.rewriteResourceURLs(in: extracted, base: base) + "\n</section>\n"
        }

        let css = Self.defaultCSS
        let html = """
        <!doctype html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <style>\(css)</style>
        </head>
        <body>
            <div id="content">\(body)</div>
        </body>
        </html>
        """
        return (html: html, baseURL: base)
    }

    private static func extractBody(html: String) -> String {
        // fast & loose: pull what’s between <body>…</body>
        guard let start = html.range(of: "<body", options: [.caseInsensitive]),
              let gt = html[start.lowerBound...].firstIndex(of: ">"),
              let end = html.range(of: "</body>", options: [.caseInsensitive]) else { return html }
        return String(html[html.index(after: gt)..<end.lowerBound])
    }

    private static func rewriteResourceURLs(in html: String, base: URL) -> String {
        // Make src/href relative resources resolvable from combined page.
        // This performs a regex replacement with a closure, rewriting only local (non-http/file/data) paths.
        let patterns = [
            "src=\"([^\"]+)\"",
            "href=\"([^\"]+)\""
        ]

        var out = html
        for p in patterns {
            out = out.replacingOccurrences(of: p) { match, matched in
                // `matched` is the full attribute text, e.g. src="images/cover.jpg"
                // Capture group 1 is the value inside the quotes.
                let whole = match.range
                let cap = match.range(at: 1)
                let capInMatch = NSRange(location: cap.location - whole.location, length: cap.length)

                // Extract the captured value from the matched substring
                let nsMatched = matched as NSString
                let val = nsMatched.substring(with: capInMatch)

                // Skip absolute/external resources
                if val.hasPrefix("http") || val.hasPrefix("file:") || val.hasPrefix("data:") {
                    return matched
                }

                // Build absolute file URL string relative to the EPUB root folder
                let abs = URL(fileURLWithPath: val, relativeTo: base).standardizedFileURL.absoluteString

                // Replace only the captured group inside the attribute
                let replaced = nsMatched.replacingCharacters(in: capInMatch, with: abs)
                return replaced
            }
        }
        return out
    }
}

// Tiny regex helper
private extension String {
    /// Regex replace with a closure. The closure receives the match object and the **matched substring**.
    func replacingOccurrences(of pattern: String, with transform: (_ match: NSTextCheckingResult, _ matched: String) -> String) -> String {
        let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

        // Work against the original string for match ranges, but build a new result with offsets.
        var result = self
        var delta = 0
        let originalNSString = self as NSString

        for m in re.matches(in: self, range: NSRange(startIndex..., in: self)) {
            // Matched substring in the ORIGINAL string
            let matched = originalNSString.substring(with: m.range)
            let replacement = transform(m, matched)

            // Apply replacement against the CURRENT result string using adjusted range
            let adjustedRange = NSRange(location: m.range.location + delta, length: m.range.length)
            result = (result as NSString).replacingCharacters(in: adjustedRange, with: replacement)

            // Track length change for subsequent ranges
            delta += replacement.count - m.range.length
        }
        return result
    }
}

private extension EPUBParser {
    static let defaultCSS = """
    :root { color-scheme: light dark; }
    body { font: -apple-system-body; line-height: 1.6; padding: 24px; margin: 0; }
    .chapter { margin: 40px 0; }
    img, svg, video, iframe { max-width: 100%; height: auto; }
    h1,h2,h3,h4 { line-height: 1.25; }
    blockquote { border-inline-start: 3px solid color-mix(in srgb, currentColor 20%, transparent); padding-inline-start: 12px; margin-inline: 0; color: color-mix(in srgb, currentColor 80%, black); }
    code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    """
}
