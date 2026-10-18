import Foundation

/// Small, safe recursive-descent calculator for the inline launcher result.
/// No `NSExpression`, no evaluating arbitrary code.
enum Calculator {
    struct Result {
        let value: Double
        let display: String
    }

    static func evaluate(_ raw: String) -> Result? {
        let input = normalize(raw)
        guard !input.isEmpty, input.count <= 256 else { return nil }
        var tokenizer = Tokenizer(input)
        guard let tokens = tokenizer.tokenize(), !tokens.isEmpty else { return nil }

        var parser = Parser(tokens: tokens)
        guard let value = parser.parse(), parser.isAtEnd, parser.hasCalculation else { return nil }
        guard value.isFinite else { return nil }
        return Result(value: value, display: format(value))
    }

    // MARK: - Input

    private static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements: [(String, String)] = [
            ("×", "*"), ("·", "*"), ("÷", "/"),
            ("−", "-"), ("–", "-"), ("—", "-"),
            ("π", "pi"), ("√", "sqrt"), ("**", "^")
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text
    }

    private static func format(_ value: Double) -> String {
        let cleaned = abs(value) < 1e-12 ? 0 : value
        let magnitude = abs(cleaned)
        if magnitude >= 1e15 || (magnitude > 0 && magnitude < 1e-8) {
            return String(format: "%.8g", cleaned)
                .replacingOccurrences(of: ".", with: ",")
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: cleaned)) ?? "\\(cleaned)"
    }

    // MARK: - Tokens

    private enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case plus, minus, star, slash, caret, percent, bang, lparen, rparen, comma
    }

    private struct Tokenizer {
        private let characters: [Character]
        private var index = 0
        private var parenDepth = 0

        init(_ text: String) {
            characters = Array(text)
        }

        mutating func tokenize() -> [Token]? {
            var tokens: [Token] = []
            while index < characters.count {
                let character = characters[index]
                if character.isWhitespace {
                    index += 1
                    continue
                }

                if character.isNumber
                    || ((character == "." || (character == "," && parenDepth == 0))
                        && index + 1 < characters.count && characters[index + 1].isNumber) {
                    guard let number = scanNumber() else { return nil }
                    tokens.append(.number(number))
                    continue
                }

                if character.isLetter {
                    let start = index
                    while index < characters.count, characters[index].isLetter {
                        index += 1
                    }
                    tokens.append(.identifier(String(characters[start..<index]).lowercased()))
                    continue
                }

                switch character {
                case "+":
                    tokens.append(.plus)
                    index += 1
                case "-":
                    tokens.append(.minus)
                    index += 1
                case "*":
                    tokens.append(.star)
                    index += 1
                case "/":
                    tokens.append(.slash)
                    index += 1
                case "^":
                    tokens.append(.caret)
                    index += 1
                case "%":
                    tokens.append(.percent)
                    index += 1
                case "!":
                    tokens.append(.bang)
                    index += 1
                case "(":
                    tokens.append(.lparen)
                    parenDepth += 1
                    index += 1
                case ")":
                    tokens.append(.rparen)
                    parenDepth = max(0, parenDepth - 1)
                    index += 1
                case ",":
                    tokens.append(.comma)
                    index += 1
                default:
                    return nil
                }
                if tokens.count > 512 { return nil }
            }
            return tokens
        }

        private mutating func scanNumber() -> Double? {
            let start = index
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    index += 1
                } else if character == "."
                            || (character == "," && parenDepth == 0) {
                    guard index + 1 < characters.count, characters[index + 1].isNumber else { break }
                    index += 1
                } else {
                    break
                }
            }
            // Scientific notation: 2.5e3, 1e-4. Only consume the exponent
            // when digits actually follow, so `2e` still means 2 * e.
            if index < characters.count, characters[index] == "e" || characters[index] == "E" {
                var probe = index + 1
                if probe < characters.count, characters[probe] == "+" || characters[probe] == "-" {
                    probe += 1
                }
                if probe < characters.count, characters[probe].isNumber {
                    index = probe
                    while index < characters.count, characters[index].isNumber {
                        index += 1
                    }
                }
            }
            guard index > start else { return nil }
            return parseNumber(String(characters[start..<index]))
        }

        private func parseNumber(_ raw: String) -> Double? {
            let lower = raw.lowercased()
            let parts = lower.split(separator: "e", maxSplits: 1, omittingEmptySubsequences: false)
            let mantissa = String(parts[0])
            let exponent = parts.count == 2 ? String(parts[1]) : nil
            let lastDot = mantissa.lastIndex(of: ".")
            let lastComma = mantissa.lastIndex(of: ",")
            let decimal: String.Index?
            switch (lastDot, lastComma) {
            case let (dot?, comma?):
                decimal = dot > comma ? dot : comma
            case let (dot?, nil):
                decimal = dot
            case let (nil, comma?):
                decimal = comma
            case (nil, nil):
                decimal = nil
            }

            let integerPart: String
            let fractionPart: String
            if let decimal {
                integerPart = mantissa[..<decimal].filter(\.isNumber)
                let after = mantissa[mantissa.index(after: decimal)...]
                fractionPart = after.filter(\.isNumber)
            } else {
                integerPart = mantissa.filter(\.isNumber)
                fractionPart = ""
            }
            guard !integerPart.isEmpty || !fractionPart.isEmpty else { return nil }
            var normalized = (integerPart.isEmpty ? "0" : integerPart)
                + (fractionPart.isEmpty ? "" : "." + fractionPart)
            if let exponent {
                normalized += "e" + exponent
            }
            return Double(normalized)
        }
    }

    // MARK: - Parser

    private struct Parser {
        private let tokens: [Token]
        private var index = 0
        private var depth = 0
        private(set) var hasCalculation = false

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        var isAtEnd: Bool { index >= tokens.count }

        private var current: Token? {
            index < tokens.count ? tokens[index] : nil
        }

        mutating func parse() -> Double? {
            guard let value = parseExpression(), isAtEnd else { return nil }
            return value
        }

        private mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let token = current, token == .plus || token == .minus {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = token == .plus ? value + rhs : value - rhs
                hasCalculation = true
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parseUnary() else { return nil }
            while let token = current {
                if token == .star || token == .slash {
                    index += 1
                    guard let rhs = parseUnary() else { return nil }
                    if token == .slash, rhs == 0 { return nil }
                    value = token == .star ? value * rhs : value / rhs
                    hasCalculation = true
                    continue
                }
                guard startsPrimary(token) else { break }
                guard let rhs = parseUnary() else { return nil }
                value *= rhs
                hasCalculation = true
            }
            return value
        }

        private mutating func parseUnary() -> Double? {
            if current == .plus {
                index += 1
                return parseUnary()
            }
            if current == .minus {
                index += 1
                guard let value = parseUnary() else { return nil }
                return -value
            }
            return parsePower()
        }

        private mutating func parsePower() -> Double? {
            guard var value = parsePostfix() else { return nil }
            if current == .caret {
                index += 1
                guard let exponent = parseUnary() else { return nil }
                value = Foundation.pow(value, exponent)
                hasCalculation = true
            }
            return value
        }

        private mutating func parsePostfix() -> Double? {
            guard var value = parsePrimary() else { return nil }
            while let token = current {
                if token == .bang {
                    guard let factorial = Self.factorial(value) else { return nil }
                    value = factorial
                    index += 1
                    hasCalculation = true
                } else if token == .percent {
                    value /= 100
                    index += 1
                    hasCalculation = true
                } else {
                    break
                }
            }
            return value
        }

        private mutating func parsePrimary() -> Double? {
            guard let token = current else { return nil }
            switch token {
            case .number(let number):
                index += 1
                return number

            case .identifier(let name):
                index += 1
                if current == .lparen {
                    guard let arguments = parseArguments() else { return nil }
                    hasCalculation = true
                    return Self.apply(name, arguments)
                }
                switch name {
                case "pi": return Double.pi
                case "e": return M_E
                case "tau": return Double.pi * 2
                default: return nil
                }

            case .lparen:
                index += 1
                depth += 1
                guard depth <= 64 else { return nil }
                guard let value = parseExpression(), current == .rparen else { return nil }
                index += 1
                depth -= 1
                return value

            default:
                return nil
            }
        }

        private mutating func parseArguments() -> [Double]? {
            guard current == .lparen else { return nil }
            index += 1
            var arguments: [Double] = []
            if current == .rparen {
                index += 1
                return arguments
            }
            while true {
                guard let argument = parseExpression() else { return nil }
                arguments.append(argument)
                guard let separator = current else { return nil }
                if separator == .comma {
                    index += 1
                    continue
                }
                if separator == .rparen {
                    index += 1
                    return arguments
                }
                return nil
            }
        }

        private func startsPrimary(_ token: Token) -> Bool {
            switch token {
            case .number, .identifier, .lparen: return true
            default: return false
            }
        }

        private static func factorial(_ value: Double) -> Double? {
            guard value >= 0, value <= 170, value.rounded() == value else { return nil }
            var result = 1.0
            var n = Int(value)
            while n > 1 {
                result *= Double(n)
                n -= 1
            }
            return result
        }

        private static func apply(_ name: String, _ args: [Double]) -> Double? {
            switch name {
            case "sqrt":
                guard args.count == 1, args[0] >= 0 else { return nil }
                return Foundation.sqrt(args[0])
            case "cbrt":
                guard args.count == 1 else { return nil }
                return Foundation.cbrt(args[0])
            case "abs":
                guard args.count == 1 else { return nil }
                return Swift.abs(args[0])
            case "round":
                guard args.count == 1 else { return nil }
                return args[0].rounded()
            case "floor":
                guard args.count == 1 else { return nil }
                return Foundation.floor(args[0])
            case "ceil":
                guard args.count == 1 else { return nil }
                return Foundation.ceil(args[0])
            case "trunc":
                guard args.count == 1 else { return nil }
                return Foundation.trunc(args[0])
            case "ln":
                guard args.count == 1, args[0] > 0 else { return nil }
                return Foundation.log(args[0])
            case "log2":
                guard args.count == 1, args[0] > 0 else { return nil }
                return Foundation.log2(args[0])
            case "log":
                if args.count == 1 {
                    guard args[0] > 0 else { return nil }
                    return Foundation.log10(args[0])
                }
                if args.count == 2 {
                    guard args[0] > 0, args[1] > 0, args[1] != 1 else { return nil }
                    return Foundation.log(args[0]) / Foundation.log(args[1])
                }
                return nil
            case "exp":
                guard args.count == 1 else { return nil }
                return Foundation.exp(args[0])
            case "sin":
                guard args.count == 1 else { return nil }
                return Foundation.sin(args[0])
            case "cos":
                guard args.count == 1 else { return nil }
                return Foundation.cos(args[0])
            case "tan":
                guard args.count == 1 else { return nil }
                return Foundation.tan(args[0])
            case "asin":
                guard args.count == 1 else { return nil }
                return Foundation.asin(args[0])
            case "acos":
                guard args.count == 1 else { return nil }
                return Foundation.acos(args[0])
            case "atan":
                guard args.count == 1 else { return nil }
                return Foundation.atan(args[0])
            case "sinh":
                guard args.count == 1 else { return nil }
                return Foundation.sinh(args[0])
            case "cosh":
                guard args.count == 1 else { return nil }
                return Foundation.cosh(args[0])
            case "tanh":
                guard args.count == 1 else { return nil }
                return Foundation.tanh(args[0])
            case "pow":
                guard args.count == 2 else { return nil }
                return Foundation.pow(args[0], args[1])
            case "mod":
                guard args.count == 2, args[1] != 0 else { return nil }
                return Foundation.fmod(args[0], args[1])
            case "hypot":
                guard args.count == 2 else { return nil }
                return Foundation.hypot(args[0], args[1])
            case "min":
                guard !args.isEmpty else { return nil }
                return args.min()
            case "max":
                guard !args.isEmpty else { return nil }
                return args.max()
            case "deg":
                guard args.count == 1 else { return nil }
                return args[0] * 180 / Double.pi
            case "rad":
                guard args.count == 1 else { return nil }
                return args[0] * Double.pi / 180
            case "fact":
                guard args.count == 1 else { return nil }
                return factorial(args[0])
            default:
                return nil
            }
        }
    }
}
