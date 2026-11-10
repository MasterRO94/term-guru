import Testing
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
