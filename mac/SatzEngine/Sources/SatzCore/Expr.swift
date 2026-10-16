import Foundation

/// Arithmetic that number fields take; see `web/src/field.ts`.
public enum Expr {
    /// Millimetres per unit that expressions may name.
    static let units: [String: Double] = ["mm": 1, "cm": 10, "pt": 25.4 / 72, "in": 25.4]

    /// The value of `source` in `unit`: + − × / and brackets over numbers, each optionally
    /// in mm, cm, pt or in; a leading +, × or / applies to `current`. Nil if `source` is
    /// not such an expression.
    public static func evaluate(_ source: String, current: Double, unit: String) -> Double? {
        var s = source.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "−", with: "-")
            .filter { !$0.isWhitespace }
        if let f = s.first, "+*/".contains(f) { s = "\(current)" + s }
        guard !s.isEmpty, let tokens = tokenize(s) else { return nil }
        var i = 0

        func expr() -> Double {
            var v = term()
            while i < tokens.count, tokens[i] == "+" || tokens[i] == "-" {
                let op = tokens[i]
                i += 1
                v = op == "+" ? v + term() : v - term()
            }
            return v
        }
        func term() -> Double {
            var v = factor()
            while i < tokens.count, tokens[i] == "*" || tokens[i] == "/" {
                let op = tokens[i]
                i += 1
                v = op == "*" ? v * factor() : v / factor()
            }
            return v
        }
        func factor() -> Double {
            guard i < tokens.count else { return .nan }
            let t = tokens[i]
            i += 1
            if t == "-" { return -factor() }
            if t == "(" {
                let v = expr()
                guard i < tokens.count, tokens[i] == ")" else { return .nan }
                i += 1
                return v
            }
            let suffix = ["mm", "cm", "pt", "in", "%"].first { t.hasSuffix($0) }
            let digits = suffix.map { String(t.dropLast($0.count)) } ?? t
            guard let n = Double(digits) else { return .nan }
            if let suffix, let from = units[suffix], let to = units[unit] { return n * from / to }
            return n
        }

        let v = expr()
        return i == tokens.count && v.isFinite ? v : nil
    }

    /// Numbers with their units, operators and brackets, or nil when something else is there.
    private static func tokenize(_ s: String) -> [String]? {
        let chars = Array(s)
        var out: [String] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if "+-*/()".contains(c) {
                out.append(String(c))
                i += 1
                continue
            }
            guard c.isNumber || c == "." else { return nil }
            var j = i
            var dots = 0
            while j < chars.count, chars[j].isNumber || chars[j] == "." {
                if chars[j] == "." { dots += 1 }
                j += 1
            }
            guard dots <= 1, chars[i..<j].contains(where: \.isNumber) else { return nil }
            if let unit = ["mm", "cm", "pt", "in", "%"].first(where: { u in
                j + u.count <= chars.count && String(chars[j..<j + u.count]) == u
            }) {
                j += unit.count
            }
            out.append(String(chars[i..<j]))
            i = j
        }
        return out
    }

    /// The step of an arrow key or a label drag: 10 with Shift, 0.1 with Option unless `integer`, else 1.
    public static func step(shift: Bool, option: Bool, integer: Bool = false) -> Double {
        shift ? 10 : option && !integer ? 0.1 : 1
    }
}
