import Testing
import Foundation
@testable import GuruCore

@Suite struct TokenizerTests {
    @Test func splitsWordsAndKeepsEmptyPartial() {
        #expect(Tokenizer.parse("git checkout ").tokens == ["git", "checkout", ""])
        #expect(Tokenizer.parse("git ch").tokens == ["git", "ch"])
    }

    @Test func keepsOnlyLastPipelineSegment() {
        #expect(Tokenizer.parse("cat a | grep f").tokens == ["grep", "f"])
        #expect(Tokenizer.parse("make && npm run ").tokens == ["npm", "run", ""])
    }

    @Test func handlesQuotesAndEscapes() {
        let line = Tokenizer.parse(#"git commit -m "hello wor"#)
        #expect(line.tokens == ["git", "commit", "-m", "hello wor"])
        #expect(line.rawPartial == #""hello wor"#)
        #expect(Tokenizer.parse(#"cd My\ Dir"#).tokens == ["cd", "My Dir"])
    }

    @Test func skipsLeadingAssignments() {
        #expect(Tokenizer.parse("FOO=1 npm run").tokens == ["npm", "run"])
    }

    @Test func redirectTargetIsFile() {
        let spaced = Tokenizer.parse("git status > ")
        #expect(spaced.tokens == ["git", "status", ""])
        #expect(spaced.redirect == .file)

        let glued = Tokenizer.parse("git status >RE")
        #expect(glued.tokens == ["git", "status", "RE"])
        #expect(glued.rawPartial == "RE")
        #expect(glued.redirect == .file)

        #expect(Tokenizer.parse("cat <").redirect == .file)
        #expect(Tokenizer.parse("cat < ").redirect == .file)
        #expect(Tokenizer.parse("cat < ").tokens == ["cat", ""])
        for op in [">>", ">|", "<>", "&>", "&>>", "2>", "2>>", "3<"] {
            let line = Tokenizer.parse("cmd \(op)ou")
            #expect(line.redirect == .file, "\(op)")
            #expect(line.tokens == ["cmd", "ou"], "\(op)")
        }
        #expect(Tokenizer.parse("cmd&>ou").tokens == ["cmd", "ou"])
    }

    @Test func dropsRedirectsBeforeTheCursorWord() {
        let dup = Tokenizer.parse("make 2>&1 -")
        #expect(dup.tokens == ["make", "-"])
        #expect(dup.redirect == nil)
        #expect(Tokenizer.parse("ls 2> err.log -").tokens == ["ls", "-"])
        #expect(Tokenizer.parse("git log > out.txt --oneline").tokens == ["git", "log", "--oneline"])
        #expect(Tokenizer.parse("cmd <&- 2>/dev/null x").tokens == ["cmd", "x"])
        #expect(Tokenizer.parse("echo a2>f b").tokens == ["echo", "a2", "b"])
    }

    @Test func heredocsAndDupsListNothing() {
        let heredoc = Tokenizer.parse("cat <<EO")
        #expect(heredoc.redirect == Redirect.none)
        #expect(heredoc.tokens == ["cat", "EO"])
        #expect(Tokenizer.parse("cat <<<wo").redirect == Redirect.none)
        #expect(Tokenizer.parse("cmd >&").redirect == Redirect.none)
        #expect(Tokenizer.parse("cmd 2>&").redirect == Redirect.none)
        #expect(Tokenizer.parse("cmd <&").redirect == Redirect.none)
    }

    @Test func ampersandSeparatesOnlyAsAndOrBackground() {
        #expect(Tokenizer.parse("ls && cd ").tokens == ["cd", ""])
        #expect(Tokenizer.parse("sleep 1 & git ").tokens == ["git", ""])
        #expect(Tokenizer.parse("ls && cd ").redirect == nil)
    }

    @Test func quotedOrEscapedOperatorsAreText() {
        let line = Tokenizer.parse(#"echo "a > b" "#)
        #expect(line.tokens == ["echo", "a > b", ""])
        #expect(line.redirect == nil)
        #expect(Tokenizer.parse(#"echo a\>b"#).tokens == ["echo", "a>b"])
    }

    @Test func quotesOnlyWhenNeeded() {
        #expect(Tokenizer.quote("plain.txt") == "plain.txt")
        #expect(Tokenizer.quote("my file(1).txt") == #"my\ file\(1\).txt"#)
    }
}

@Suite struct FuzzyTests {
    @Test func prefixBeatsSubsequence() {
        let prefix = Fuzzy.score("ch", in: "checkout")!
        let scattered = Fuzzy.score("ch", in: "cherry-pick")!
        let loose = Fuzzy.score("ch", in: "cache")!
        #expect(prefix >= scattered)
        #expect(scattered > loose)
        #expect(Fuzzy.score("xyz", in: "checkout") == nil)
    }

    @Test func historyParsesExtendedFormat() {
        let parsed = HistoryStore.parse(": 1700000000:0;git status\nls -la\n: 1700000001:0;echo a\\\nb\n")
        #expect(parsed == ["git status", "ls -la"])
    }
}

@Suite struct RedirectEngineTests {
    @Test func redirectTargetsListOnlyFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let specs = root.appendingPathComponent("specs")
        try FileManager.default.createDirectory(at: specs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("app"), withIntermediateDirectories: true)
        try #"var spec={name:"tool",options:[{name:"--opt"}],args:{name:"x"}};export{spec as default};"#
            .write(to: specs.appendingPathComponent("tool.js"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let engine = Engine(specs: SpecRuntime(directories: [specs]), history: HistoryStore(files: []))
        func names(_ line: String) -> [String] {
            engine.suggest(EngineRequest(buffer: line, cursor: line.count, cwd: root.path, path: "")).map(\.name)
        }
        #expect(Set(names("tool > ")) == ["app", "notes.txt", "specs"])
        #expect(names("tool >no") == ["notes.txt"])
        #expect(names("tool 2>&1 -") == ["--opt"])
        #expect(names("tool <<E").isEmpty)
        #expect(names("tool 2>&").isEmpty)
    }
}
