import Testing

@testable import SatzCore

struct ExprTests {
    func e(_ s: String, _ cur: Double = 0, _ unit: String = "mm") -> Double? { Expr.evaluate(s, current: cur, unit: unit) }

    @Test func numbersWithACommaOrAPoint() {
        #expect(e("12,5") == 12.5)
        #expect(e(" .5 ") == 0.5)
    }

    @Test func precedenceAndBrackets() {
        #expect(e("2+3*4") == 14)
        #expect(e("(2+3)×4") == 20)
        #expect(e("10 − 2 x 3") == 4)
        #expect(e("-(4-6)") == 2)
    }

    @Test func aLeadingOperatorAppliesToTheCurrentValue() {
        #expect(e("+5", 10) == 15)
        #expect(e("*2", 10) == 20)
        #expect(e("/4", 10) == 2.5)
        #expect(e("-5", 10) == -5)
    }

    @Test func unitsConvert() {
        #expect(e("1cm") == 10)
        #expect(abs(e("1in")! - 25.4) < 1e-9)
        #expect(abs(e("72pt")! - 25.4) < 1e-9)
        #expect(abs(e("1in", 0, "pt")! - 72) < 1e-9)
        #expect(e("10mm + 1cm") == 20)
        #expect(e("50%", 0, "%") == 50)
        #expect(e("3mm", 0, "°") == 3)
    }

    @Test func whatIsNotAnExpressionIsNil() {
        for s in ["", "abc", "1+", "(1", "1)", "2..3", "1/0", "5km"] { #expect(e(s, 1) == nil, "\(s)") }
    }

    @Test func steps() {
        #expect(Expr.step(shift: false, option: false) == 1)
        #expect(Expr.step(shift: true, option: false) == 10)
        #expect(Expr.step(shift: false, option: true) == 0.1)
        #expect(Expr.step(shift: false, option: true, integer: true) == 1)
    }
}
