import Testing
@testable import GuruCore

@Suite struct RunSuggestionTests {
    private func promote(_ items: [Suggestion], _ buffer: String, cursor: Int? = nil) -> [Suggestion] {
        RunSuggestion.promote(items, buffer: buffer, cursor: cursor ?? buffer.count)
    }

    private func target(_ name: String, replace: Int) -> Suggestion {
        Suggestion(name: name, insert: name + " ", kind: .argument, replace: replace)
    }

    private func history(_ line: String, replace: Int) -> Suggestion {
        Suggestion(name: line, insert: line, kind: .history, replace: replace)
    }

    private func folder(_ name: String, replace: Int = 0) -> Suggestion {
        Suggestion(name: name, insert: name + "/", kind: .folder, replace: replace)
    }

    @Test func emptyWordRunsTheLineEvenWithHistoryOnTop() {
        let items = [history("make cu.p up", replace: 10), target("db", replace: 0)]
        let result = promote(items, "make cu.p ")
        #expect(result.map(\.kind) == [.run, .history, .argument])
        #expect(result.first?.display == "make cu.p")
        #expect(Array(result.dropFirst()) == items)
    }

    @Test func tabOnAnEmptyWordInsertsTheFirstSuggestion() {
        let run = promote([target("db", replace: 0)], "make ").first
        #expect(run?.insert == "db " && run?.replace == 0)
    }

    @Test func exactMatchBecomesTheRunRow() {
        let items = [history("make cue", replace: 7), target("cu", replace: 2), target("cu.p", replace: 2)]
        let result = promote(items, "make cu")
        #expect(result.map(\.name) == ["make cu", "make cue", "cu.p"])
        #expect(result.first?.kind == .run)
        #expect(result.first?.insert == "cu " && result.first?.replace == 2)
    }

    @Test func exactFirstWordRuns() {
        let git = Suggestion(name: "git", insert: "git ", kind: .command, replace: 3)
        #expect(promote([git], "git").map(\.kind) == [.run])
    }

    @Test func halfTypedWordCompletes() {
        let items = [target("checkout", replace: 2)]
        #expect(promote(items, "git ch") == items)
        let option = [Suggestion(name: "--file", insert: "--file=", kind: .option, replace: 6)]
        #expect(promote(option, "make --file") == option)
    }

    @Test func folderPathRuns() {
        #expect(promote([history("cd src/app", replace: 7), folder("app")], "cd src/").map(\.kind) == [.run, .history, .folder])
        let file = Suggestion(name: "a.txt", insert: "a.txt ", kind: .file)
        #expect(promote([file], "cat src/").first?.kind == .run)
    }

    @Test func slashInABranchNameCompletes() {
        let items = [target("feature/login", replace: 8)]
        #expect(promote(items, "git checkout feature/") == items)
    }

    @Test func redirectTargetsCompleteUntilTheyMatch() {
        let items = [folder("src")]
        #expect(promote(items, "echo hi > ") == items)
        #expect(promote(items, "echo hi > src/") == items)
        let file = Suggestion(name: "out", insert: "out ", kind: .file, replace: 3)
        #expect(promote([file], "echo hi > out").first?.kind == .run)
    }

    @Test func nothingToSuggestStaysEmpty() {
        #expect(promote([], "make ").isEmpty)
    }

    @Test func showsTheWholeLineWhenTheCursorIsInside() {
        #expect(promote([target("db", replace: 0)], "make  | less", cursor: 5).first?.display == "make  | less")
    }
}
