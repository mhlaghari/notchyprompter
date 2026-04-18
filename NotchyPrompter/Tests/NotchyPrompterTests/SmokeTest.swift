// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import NotchyPrompter

final class SmokeTest: XCTestCase {
    func testPathsResolve() {
        XCTAssertTrue(Paths.appSupportDir.path.contains("NotchyPrompter"))
    }
}
