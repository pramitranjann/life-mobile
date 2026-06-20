import XCTest
@testable import PRLifeKit

final class GlobalHotKeyTests: XCTestCase {
    func test_defaultBindings_coverAllContexts_withCtrlOpt() {
        let bindings = HotKeyBinding.defaults
        XCTAssertEqual(bindings.count, 4)
        XCTAssertEqual(Set(bindings.map(\.context)),
                       Set([.quick, .work, .journal, .ideas]))
        // Control(0x1000) + Option(0x0800) on every chord.
        for binding in bindings {
            XCTAssertEqual(binding.modifiers, 0x1000 | 0x0800)
        }
    }

    func test_defaultBindings_useExpectedKeyCodes() {
        let byContext = Dictionary(uniqueKeysWithValues: HotKeyBinding.defaults.map { ($0.context, $0.keyCode) })
        XCTAssertEqual(byContext[.quick], 49)   // Space
        XCTAssertEqual(byContext[.work], 13)    // W
        XCTAssertEqual(byContext[.journal], 38) // J
        XCTAssertEqual(byContext[.ideas], 34)   // I
    }
}
