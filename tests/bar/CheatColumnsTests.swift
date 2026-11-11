import Testing
@testable import CheatsheetPanel

struct CheatColumnsTests {
    @Test("sections spread over the columns, and a long one continues under its title")
    func balance() {
        let entries = (0..<4).map { CheatEntry(group: "A", key: "k\($0)", action: "a") }
            + (0..<20).map { CheatEntry(group: "B", key: "k\($0)", action: "b") }
        let columns = cheatColumns(entries, count: 3)
        #expect(columns.count == 3)
        #expect(columns.flatMap { $0 }.reduce(0) { $0 + $1.rows.count } == 24)
        #expect(columns[1].first?.title == "B" && columns[2].first?.title == "B")
    }
}
