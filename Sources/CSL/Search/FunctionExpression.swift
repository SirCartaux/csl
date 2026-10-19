import Foundation

/// A bounded, compiled expression tree. User input is never executed as code.
struct FunctionExpression {
    let source: String
    private let tree: Node

    static func body(of raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let equal = text.firstIndex(of: "=") {
            let lhs = text[..<equal].filter { !$0.isWhitespace }
            guard lhs == "y" || lhs == "f(x)" else { return nil }
            return String(text[text.index(after: equal)...])
        }
        guard text.range(of: #"\bx\b"#, options: .regularExpression) != nil
                || text.range(of: #"[0-9]x\b"#, options: .regularExpression) != nil else { return nil }
        return text
    }

    init(_ raw: String) throws {
        guard var text = Self.body(of: raw), text.count <= 256 else { throw ParseError.invalid }
        for (from, to) in [("×", "*"), ("·", "*"), ("÷", "/"), ("−", "-"),
                           ("π", "pi"), ("√", "sqrt"), ("**", "^"), ("²", "^2"), ("³", "^3")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parser = try Parser(text)
        tree = try parser.expression()
        guard parser.current == .end else { throw ParseError.invalid }
    }

    func value(at x: Double) -> Double { tree.value(x) }
    enum ParseError: Error { case invalid }

    private indirect enum Node {
        case number(Double), x, negative(Node), binary(Character, Node, Node), call(String, [Node])
        func value(_ x: Double) -> Double {
            switch self {
            case .number(let n): return n
            case .x: return x
            case .negative(let n): return -n.value(x)
            case .binary(let op, let a, let b):
                let l = a.value(x), r = b.value(x)
                switch op {
                case "+": return l + r
                case "-": return l - r
                case "*": return l * r
                case "/": return r == 0 ? .nan : l / r
                default: return pow(l, r)
                }
            case .call(let name, let args):
                let a = args[0].value(x)
                switch name {
                case "sin": return sin(a)
                case "cos": return cos(a)
                case "tan": return abs(cos(a)) < 1e-14 ? .nan : tan(a)
                case "asin": return asin(a)
                case "acos": return acos(a)
                case "atan": return atan(a)
                case "sinh": return sinh(a)
                case "cosh": return cosh(a)
                case "tanh": return tanh(a)
                case "sqrt": return sqrt(a)
                case "cbrt": return cbrt(a)
                case "abs": return abs(a)
                case "exp": return exp(a)
                case "ln": return log(a)
                case "log": return log10(a)
                case "log2": return log2(a)
                case "floor": return floor(a)
                case "ceil": return ceil(a)
                case "round": return a.rounded()
                case "pow": return pow(a, args[1].value(x))
                case "min": return min(a, args[1].value(x))
                case "max": return max(a, args[1].value(x))
                default: return .nan
                }
            }
        }
    }

    private enum Token: Equatable {
        case number(Double), name(String), symbol(Character), end
    }
    private struct Parser {
        var tokens: [Token] = []
        var index = 0
        var depth = 0
        var current: Token { index < tokens.count ? tokens[index] : .end }
        init(_ text: String) throws {
            let chars = Array(text)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace { i += 1; continue }
                if c.isNumber || c == "." || c == "," {
                    let start = i
                    var decimal = false
                    while i < chars.count {
                        if chars[i].isNumber { i += 1 }
                        else if (chars[i] == "." || chars[i] == ",") && !decimal {
                            decimal = true; i += 1
                        } else { break }
                    }
                    if i < chars.count, chars[i] == "e" {
                        var end = i + 1
                        if end < chars.count, chars[end] == "+" || chars[end] == "-" { end += 1 }
                        let digits = end
                        while end < chars.count, chars[end].isNumber { end += 1 }
                        if end > digits { i = end }
                    }
                    guard let n = Double(String(chars[start..<i]).replacingOccurrences(of: ",", with: ".")), n.isFinite else { throw ParseError.invalid }
                    tokens.append(.number(n))
                } else if c.isLetter {
                    // x is always a variable, including x(x+1) and 2x.
                    if c == "x" { tokens.append(.name("x")); i += 1; continue }
                    let start = i
                    while i < chars.count, chars[i].isLetter { i += 1 }
                    if String(chars[start..<i]) == "log", i < chars.count, chars[i] == "2" { i += 1 }
                    tokens.append(.name(String(chars[start..<i])))
                } else if "+-*/^();".contains(c) {
                    tokens.append(.symbol(c)); i += 1
                } else { throw ParseError.invalid }
            }
        }
        mutating func take(_ c: Character) -> Bool {
            guard current == .symbol(c) else { return false }
            index += 1; return true
        }
        mutating func expression() throws -> Node {
            var node = try term()
            while current == .symbol("+") || current == .symbol("-") {
                let op: Character = take("+") ? "+" : "-"
                if op == "-" { index += 1 }
                node = .binary(op, node, try term())
            }
            return node
        }
        mutating func term() throws -> Node {
            var node = try unary()
            while true {
                if take("*") { node = .binary("*", node, try unary()) }
                else if take("/") { node = .binary("/", node, try unary()) }
                else {
                    switch current {
                    case .name, .number, .symbol("("): node = .binary("*", node, try unary())
                    default: return node
                    }
                }
            }
        }
        mutating func unary() throws -> Node {
            depth += 1
            defer { depth -= 1 }
            guard depth <= 64 else { throw ParseError.invalid }
            if take("+") { return try unary() }
            if take("-") { return .negative(try unary()) }
            let node = try primary()
            if take("^") { return .binary("^", node, try unary()) }
            return node
        }
        mutating func primary() throws -> Node {
            let token = current
            index += 1
            switch token {
            case .number(let n): return .number(n)
            case .name("x"): return .x
            case .name("pi"): return .number(.pi)
            case .name("e"): return .number(M_E)
            case .name("tau"): return .number(2 * .pi)
            case .name(let name):
                let one = ["sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "sqrt", "cbrt", "abs", "exp", "ln", "log", "log2", "floor", "ceil", "round"]
                let two = ["pow", "min", "max"]
                guard one.contains(name) || two.contains(name), take("(") else { throw ParseError.invalid }
                var args = [try expression()]
                // Semicolon separates arguments; comma is the decimal separator.
                if take(";") { args.append(try expression()) }
                guard take(")"), args.count == (two.contains(name) ? 2 : 1) else { throw ParseError.invalid }
                return .call(name, args)
            case .symbol("("):
                let node = try expression()
                guard take(")") else { throw ParseError.invalid }
                return node
            default: throw ParseError.invalid
            }
        }
    }
}
