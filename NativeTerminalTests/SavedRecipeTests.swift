import Foundation
import Testing
@testable import NativeTerminal

/// “Guardar como receta”: the words, the asked-for values and the folder.
@MainActor
struct SavedRecipeTests {
    @Test func splitsWordsKeepingQuotes() {
        #expect(SavedRecipe.rawWords(#"git commit -m "primer cambio"  && ls"#)
            == ["git", "commit", "-m", #""primer cambio""#, "&&", "ls"])
        #expect(SavedRecipe.rawWords(#"open My\ File.txt"#) == ["open", #"My\ File.txt"#])
    }

    @Test func keepsTheLinesOfAScript() {
        let script = """
            PROFILE="$HOME/Library/Application Support/ChatGPT Personal"
            mkdir -p "$PROFILE" "$HOME/.codex-personal"
            CODEX_HOME="$HOME/.codex-personal" \\
            "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT" \\
            --user-data-dir="$PROFILE"

            """
        let words = SavedRecipe.rawWords(script)
        #expect(words == [
            #"PROFILE="$HOME/Library/Application Support/ChatGPT Personal""#, "\n",
            "mkdir", "-p", #""$PROFILE""#, #""$HOME/.codex-personal""#, "\n",
            #"CODEX_HOME="$HOME/.codex-personal""#, #""/Applications/ChatGPT.app/Contents/MacOS/ChatGPT""#,
            #"--user-data-dir="$PROFILE""#,
        ])
        let saved = SavedRecipe(title: "", command: script, directory: "/tmp")
        #expect(saved.command == """
            PROFILE="$HOME/Library/Application Support/ChatGPT Personal"
            mkdir -p "$PROFILE" "$HOME/.codex-personal"
            CODEX_HOME="$HOME/.codex-personal" "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT" --user-data-dir="$PROFILE"
            """)
        saved.parameters = [SavedRecipeParameter(wordIndex: 4, label: "Carpeta")]
        #expect(saved.recipe(in: "/tmp").command(with: ["w4": "/tmp/otra"]).hasPrefix("""
            PROFILE="$HOME/Library/Application Support/ChatGPT Personal"
            mkdir -p /tmp/otra
            """))
    }

    @Test func asksForAWordAndQuotesTheAnswer() {
        let saved = SavedRecipe(title: "Levantar la tienda", command: "npm run dev -- --port 4321", directory: "/tmp/tienda")
        saved.parameters = [SavedRecipeParameter(wordIndex: 5, label: "Puerto")]
        let recipe = saved.recipe(in: "/tmp/tienda")

        #expect(recipe.parameters.map(\.label) == ["Puerto"])
        #expect(recipe.parameters.first?.defaultValue == "4321")
        #expect(recipe.command(with: [:]) == "npm run dev -- --port 4321")
        #expect(recipe.command(with: ["w5": "8080"]) == "npm run dev -- --port 8080")
        #expect(recipe.command(with: ["w5": "mi puerto"]) == "npm run dev -- --port 'mi puerto'")
    }

    @Test func keepsTheOriginalQuotingWhenTheValueIsUnchanged() {
        let saved = SavedRecipe(title: "", command: #"git commit -m "primer cambio""#, directory: "/tmp")
        saved.parameters = [SavedRecipeParameter(wordIndex: 3, label: "Mensaje")]
        let recipe = saved.recipe(in: "/tmp")
        #expect(recipe.command(with: [:]) == #"git commit -m "primer cambio""#)
        #expect(recipe.command(with: ["w3": "arreglo"]) == "git commit -m arreglo")
        #expect(recipe.title == #"git commit -m "primer cambio""#)
    }

    @Test func goesToItsFolderOnlyWhenTiedToIt() {
        let saved = SavedRecipe(title: "Pruebas", command: "npm test", directory: "/tmp/tienda web")
        #expect(saved.recipe(in: "/tmp/otra").command(with: [:]) == "npm test")
        saved.staysInFolder = true
        #expect(saved.recipe(in: "/tmp/otra").command(with: [:]) == "cd '/tmp/tienda web' && npm test")
        #expect(saved.recipe(in: "/tmp/tienda web").command(with: [:]) == "npm test")
    }

    @Test func theAssistantUsesTheRecipeAskedForInWords() async {
        let clone = SavedRecipe(title: "Levantar un clon de ChatGPT", command: #"open -n -a ChatGPT --args --user-data-dir="$HOME/perfil""#, directory: "/tmp")
        let other = SavedRecipe(title: "Levantar la tienda", command: "npm run dev", directory: "/tmp/tienda")
        var inventory = ToolInventory(directory: "/tmp", executables: ["open", "npm"])
        inventory.savedRecipes = [other, clone].map { $0.recipe(in: "/tmp") }

        for request in ["Hola, quiero levantar el clon de chatgpt", "Hola, quiero abrir un clon de ChatGPT"] {
            let reply = await AssistantEngine.plainReply(to: request, inventory: inventory, conversational: true)
            #expect(reply.proposals.first?.command == clone.command)
            #expect(reply.proposals.first?.tool == "Tu receta «Levantar un clon de ChatGPT»")
            #expect(reply.explanation.contains("Levantar un clon de ChatGPT"))
        }
        #expect(AssistantEngine.savedRecipe(for: "levanta la tienda", inventory: inventory)?.title == "Levantar la tienda")
        #expect(AssistantEngine.savedRecipe(for: "comprime un audio", inventory: inventory) == nil)
        // Other words for the same thing.
        for request in ["Quiero abrir otro ChatGPT, porfa", "abre un segundo ChatGPT", "corre mi receta de ChatGPT"] {
            #expect(AssistantEngine.savedRecipe(for: request, inventory: inventory)?.title == "Levantar un clon de ChatGPT", "\(request)")
        }
        // The app itself, and a question, aren't the recipe.
        #expect(AssistantEngine.savedRecipe(for: "abre ChatGPT", inventory: inventory) == nil)
        #expect(AssistantEngine.savedRecipe(for: "¿qué es ChatGPT?", inventory: inventory) == nil)
    }

    @Test func suggestsASymbolForTheProgram() {
        #expect(RecipeSymbolPicker.suggestedSymbol(for: "git status") == "arrow.triangle.branch")
        #expect(RecipeSymbolPicker.suggestedSymbol(for: "FOO=1 npm run dev") == "shippingbox.fill")
        #expect(RecipeSymbolPicker.suggestedSymbol(for: "htop") == "terminal")
    }
}
