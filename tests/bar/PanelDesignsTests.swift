import Testing
@testable import PanelDesigns

@Suite struct PanelDesignsTests {
    @Test("every popup design in the list draws, for the bar and the settings thumbnails")
    func everyDesignDraws() {
        for (kind, designs) in panelDesignNames {
            #expect(designs.first?.value == nil, "\(kind): the default design comes first")
            #expect(Set(designs.map(\.value)).count == designs.count, "\(kind): a design name is repeated")
            for design in designs {
                #expect(designPreview(kind: kind, design: design.value) != nil, "\(kind) \(design.title)")
            }
        }
    }
}
