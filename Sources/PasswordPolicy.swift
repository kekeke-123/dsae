import Foundation

/// 口令规则：至少 4 位；只能数字或英文字母；不能全同、不能顺子、不能重复片段。
enum PasswordPolicy {

    static let minimumLength = 4
    static let ruleText = "至少 4 位，只能用数字或英文字母；不能全部相同、不能连续（1234 / abcd / 9876），也不能是重复片段（1212 / abab）。"

    static func problem(with password: String) -> String? {
        if password.count < minimumLength {
            return "口令至少 \(minimumLength) 位。"
        }

        let allowed = CharacterSet.alphanumerics
        for scalar in password.unicodeScalars {
            guard scalar.value < 128, allowed.contains(scalar) else {
                return "口令只能用数字或英文字母。"
            }
        }

        let chars = Array(password.lowercased())
        if Set(chars).count == 1 {
            return "口令不能全部是同一个字符。"
        }
        if isSequential(chars) {
            return "口令不能是连续的顺子，例如 1234、abcd、9876。"
        }
        if isRepeatedBlock(chars) {
            return "口令不能是重复片段，例如 1212、abab。"
        }
        return nil
    }

    private static func indexValue(_ character: Character) -> Int? {
        if character.isNumber, let digit = character.wholeNumberValue {
            return digit
        }
        if character.isLetter, let ascii = character.asciiValue {
            return Int(ascii)
        }
        return nil
    }

    private static func isSequential(_ chars: [Character]) -> Bool {
        guard chars.count > 1 else { return false }
        var values = [Int]()
        for character in chars {
            guard let value = indexValue(character) else { return false }
            values.append(value)
        }
        var steps = [Int]()
        for index in 1..<values.count {
            steps.append(values[index] - values[index - 1])
        }
        return steps.allSatisfy { $0 == 1 } || steps.allSatisfy { $0 == -1 }
    }

    private static func isRepeatedBlock(_ chars: [Character]) -> Bool {
        let count = chars.count
        guard count >= 2 else { return false }
        for size in 1...(count / 2) where count % size == 0 {
            let block = Array(chars[0..<size])
            var index = size
            var repeated = true
            while index < count {
                let next = Array(chars[index..<(index + size)])
                if next != block {
                    repeated = false
                    break
                }
                index += size
            }
            if repeated { return true }
        }
        return false
    }
}
