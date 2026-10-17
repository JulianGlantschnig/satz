import Foundation
import Testing

@testable import Satz

@MainActor
struct UnitsTests {
    @Test func lengthsShowInTheChosenUnit() {
        let a4 = Units.a4.width
        #expect(Units.format(a4, unit: .mm) == 210.formatted() + " mm")
        #expect(Units.format(a4, unit: .cm) == 21.formatted() + " cm")
        #expect(Units.format(72, unit: .in) == 1.formatted() + " in")
        #expect(Units.format(a4, unit: .pt) == 595.3.formatted() + " pt")
    }

    @Test func aFieldCountsInTheUnitOfTheSettings() {
        let before = UserDefaults.standard.string(forKey: Units.key)
        defer { UserDefaults.standard.set(before, forKey: Units.key) }
        UserDefaults.standard.set("in", forKey: Units.key)
        #expect(NumberField.Unit.length.name == "in")
        #expect(NumberField.Unit.length.scale == 72)
        UserDefaults.standard.set("cm", forKey: Units.key)
        #expect(NumberField.Unit.length.scale == 720 / 25.4)
    }

    @Test func theExamplesComeWithTheApp() throws {
        for e in Example.all { #expect(try !e.data().isEmpty) }
    }
}
