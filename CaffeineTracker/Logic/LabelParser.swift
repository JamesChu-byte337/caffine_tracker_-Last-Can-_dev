import Foundation

struct LabelScanResult: Equatable {
    /// Caffeine per serving. Calculated from a per-100 mL value when the label gives one and a serving size is found.
    var caffeineMg: Double?
    var servingML: Double?
    /// Set when the label states caffeine per 100 mL.
    var per100mLMg: Double?
    /// The text the caffeine amount was read from, shown to the user for checking.
    var matchedText: String?
}

/// Finds a caffeine amount and serving size in text read from a drink label.
/// Results always go to the user to confirm before use.
enum LabelParser {
    private static let number = #"(\d+(?:[.,]\d+)?)"#
    private static let caffeineWord = #"caf{1,2}[eé]ine"#

    static func parse(lines: [String]) -> LabelScanResult {
        parse(text: lines.joined(separator: " "))
    }

    static func parse(text raw: String) -> LabelScanResult {
        let text = raw.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        var result = LabelScanResult()
        result.servingML = servingSize(in: text)

        let per100 = #"(\s*(?:/|per|par)\s*100\s*ml)?"#
        let caffeineFirst = caffeineWord + #"[^0-9]{0,40}?"# + number + #"\s*mg"# + per100
        let amountFirst = number + #"\s*mg"# + per100 + #"\s*(?:of\s+|de\s+)?"# + caffeineWord

        guard let match = firstMatch(caffeineFirst, in: text) ?? firstMatch(amountFirst, in: text),
              let amount = parseNumber(match.groups[0]) else { return result }

        result.matchedText = match.whole
        if match.groups[1] != nil {
            result.per100mLMg = amount
            if let serving = result.servingML {
                result.caffeineMg = (amount * serving / 100).rounded()
            }
        } else {
            result.caffeineMg = amount
        }
        return result
    }

    static func servingSize(in text: String) -> Double? {
        let labelled = #"(?:serving size|per serving|serving|portion)[^0-9]{0,20}"# + number + #"\s*ml"#
        if let match = firstMatch(labelled, in: text), let ml = parseNumber(match.groups[0]) {
            return ml
        }
        // Otherwise take the largest volume printed, which is usually the container size (e.g. "473 mL").
        // 100 mL is skipped because it's almost always the "per 100 mL" reference amount, not a serving.
        let volumes = allMatches(number + #"\s*ml\b"#, in: text).compactMap { parseNumber($0.groups[0]) }
        if let largest = volumes.filter({ $0 != 100 }).max() {
            return largest
        }
        if let match = firstMatch(number + #"\s*fl\.?\s*oz"#, in: text), let oz = parseNumber(match.groups[0]) {
            return (oz * 29.5735).rounded()
        }
        return nil
    }

    // MARK: - Regex helpers

    private struct Match {
        let whole: String
        let groups: [String?]
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Match? {
        allMatches(pattern, in: text).first
    }

    private static func allMatches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { result in
            let groups = (1..<result.numberOfRanges).map { index -> String? in
                let range = result.range(at: index)
                return range.location == NSNotFound ? nil : nsText.substring(with: range)
            }
            return Match(whole: nsText.substring(with: result.range), groups: groups)
        }
    }

    private static func parseNumber(_ string: String?) -> Double? {
        guard let string else { return nil }
        return Double(string.replacingOccurrences(of: ",", with: "."))
    }
}
