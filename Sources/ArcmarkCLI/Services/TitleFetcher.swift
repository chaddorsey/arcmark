import Foundation

/// Lightweight async title fetcher for CLI use. Fetches the <title> tag from a URL.
/// Foundation-only — no AppKit dependency. Based on LinkTitleService's extraction logic.
enum TitleFetcher {

    /// Fetch the HTML <title> for a URL. Returns nil on failure (network error, no title tag, timeout).
    static func fetchTitle(for url: URL) async -> String? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = ["Accept": "text/html,application/xhtml+xml"]
        let session = URLSession(configuration: config)

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            let limitedData = data.prefix(200_000)
            let encoding = stringEncoding(from: response) ?? .utf8
            let html = String(data: limitedData, encoding: encoding) ?? String(data: limitedData, encoding: .utf8)
            guard let html, let title = extractTitle(from: html) else {
                return nil
            }

            var cleaned = decodeHTMLEntities(title)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
            // Collapse runs of whitespace (not just pairs)
            while cleaned.contains("  ") {
                cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    private static func stringEncoding(from response: URLResponse) -> String.Encoding? {
        if let textEncodingName = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(textEncodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                return String.Encoding(rawValue: nsEncoding)
            }
        }
        return nil
    }

    private static func extractTitle(from html: String) -> String? {
        let lower = html.lowercased()
        guard let startRange = lower.range(of: "<title") else { return nil }
        guard let tagEndRange = lower.range(of: ">", range: startRange.upperBound..<lower.endIndex) else { return nil }
        guard let endRange = lower.range(of: "</title>", range: tagEndRange.upperBound..<lower.endIndex) else { return nil }
        let rawTitle = html[tagEndRange.upperBound..<endRange.lowerBound]
        return String(rawTitle)
    }

    /// Decode common HTML entities. Handles named entities and numeric (decimal + hex) references.
    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        // Named entities
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
            "&#39;": "'", "&nbsp;": " ", "&mdash;": "\u{2014}", "&ndash;": "\u{2013}",
            "&laquo;": "\u{00AB}", "&raquo;": "\u{00BB}", "&copy;": "\u{00A9}",
            "&reg;": "\u{00AE}", "&trade;": "\u{2122}", "&hellip;": "\u{2026}",
        ]
        for (entity, char) in named {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Numeric decimal: &#123;
        while let range = result.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let match = String(result[range])
            let digits = match.dropFirst(2).dropLast(1)
            if let code = UInt32(digits), let scalar = Unicode.Scalar(code) {
                result.replaceSubrange(range, with: String(scalar))
            } else {
                break
            }
        }
        // Numeric hex: &#x1F4A9;
        while let range = result.range(of: #"&#x([0-9a-fA-F]+);"#, options: .regularExpression) {
            let match = String(result[range])
            let hex = match.dropFirst(3).dropLast(1)
            if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                result.replaceSubrange(range, with: String(scalar))
            } else {
                break
            }
        }
        return result
    }
}
