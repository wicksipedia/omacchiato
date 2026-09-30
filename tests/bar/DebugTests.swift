import Testing
@testable import omacchiato_bar

@Suite struct DebugTests {
    @Test("the memory line gives the footprint and the malloc bytes in use, in MB")
    func memory() {
        #expect(memoryLine(footprint: 109_261_619, mallocInUse: 36_805_427)
                == "memory: footprint 104.2 MB, malloc 35.1 MB in use")
    }
}
