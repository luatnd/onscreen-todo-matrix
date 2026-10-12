import Testing
@testable import OTMCore

@Test func coreVersionIsSet() {
    #expect(OTMCoreVersion.string == "1.0.0")
}
