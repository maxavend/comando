import Testing
@testable import NativeTerminal

struct CommandExplainerTests {
    @Test func explainsCombinedFlags() {
        let parts = CommandExplainer.parts(of: "ls -lh ~/Documents")
        #expect(parts.map(\.token) == ["ls", "-lh", "~/Documents"])
        #expect(parts[1].explanation == "-l: en detalle · -h: tamaños legibles")
        #expect(parts[2].explanation == "Un archivo o carpeta")
    }

    @Test func explainsPipesAndSubcommands() {
        let parts = CommandExplainer.parts(of: "git log --oneline | head -n 5")
        #expect(parts.map(\.token) == ["git", "log", "--oneline", "|", "head", "-n", "5"])
        #expect(parts[2].explanation == "un commit por línea")
        #expect(parts[3].explanation == "Pasa el resultado al comando siguiente")
        #expect(parts[5].explanation == "cuántas líneas")
    }

    @Test func keepsQuotedText() {
        #expect(CommandExplainer.tokens(#"grep -rn "hola mundo" ."#) == ["grep", "-rn", "\"hola mundo\"", "."])
    }
}

struct TrashConverterTests {
    @Test func convertsRm() {
        #expect(TrashConverter.trashCommand(for: "rm -rf build") == "trash build")
        #expect(TrashConverter.trashCommand(for: #"rm "a b.txt" c"#) == #"trash "a b.txt" c"#)
        #expect(TrashConverter.trashCommand(for: "rm -- -weird") == "trash -weird")
        #expect(TrashConverter.trashCommand(for: "rm -rf") == nil)
        #expect(TrashConverter.trashCommand(for: "rm a && ls") == nil)
        #expect(TrashConverter.trashCommand(for: "ls") == nil)
    }
}

struct ProgressParserTests {
    @Test func readsPercentages() {
        let progress = ProgressParser.parse("Downloading model [=====>     ] 45%")
        #expect(progress?.fraction == 0.45)
        #expect(progress?.label == "Downloading model 45%")
        #expect(ProgressParser.parse("████████░░░░ 66.5 %")?.fraction == 0.665)
        #expect(ProgressParser.parse("[12/48] Compiling")?.fraction == 0.25)
        #expect(ProgressParser.parse("hola mundo") == nil)
        #expect(ProgressParser.parse("version 1/2") == nil)
    }
}

struct GitInfoTests {
    @Test func parsesStatus() {
        #expect(GitInfo.parse(porcelain: "## main...origin/main [ahead 1]\n M a.swift\n?? b.txt\n") == GitInfo(branch: "main", changes: 2))
        #expect(GitInfo.parse(porcelain: "## No commits yet on feature\n") == GitInfo(branch: "feature", changes: 0))
        #expect(GitInfo.parse(porcelain: "") == nil)
    }
}
