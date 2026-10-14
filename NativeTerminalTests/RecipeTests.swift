import Testing
@testable import NativeTerminal

struct RecipeTests {
    @Test func searchFindsByPlainWords() {
        #expect(RecipeBook.search("comprimir").contains { $0.id == "zip" })
        #expect(RecipeBook.search("puerto").contains { $0.id == "port" })
        #expect(RecipeBook.search("ESPACIO").contains { $0.id == "df" })
        #expect(RecipeBook.search("").count == RecipeBook.all.count)
    }

    @Test func buildsQuotedCommands() throws {
        let zip = try #require(RecipeBook.all.first { $0.id == "zip" })
        #expect(zip.command(with: ["folder": "Mis Fotos"]) == "zip -r 'Mis Fotos.zip' 'Mis Fotos'")
        let find = try #require(RecipeBook.all.first { $0.id == "find" })
        #expect(find.command(with: ["text": "it's"]) == #"find . -iname '*it'\''s*'"#)
    }

    @Test func requiresValuesWithoutDefaults() throws {
        let port = try #require(RecipeBook.all.first { $0.id == "port" })
        #expect(!port.isComplete([:]))
        #expect(port.command(with: ["port": "6006"]) == "lsof -nP -iTCP:6006 -sTCP:LISTEN")
        let serve = try #require(RecipeBook.all.first { $0.id == "serve" })
        #expect(serve.isComplete([:]))
        #expect(serve.command(with: [:]) == "python3 -m http.server 8000")
    }
}
