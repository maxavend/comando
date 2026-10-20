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

    @Test func suggestsASymbolForTheProgram() {
        #expect(RecipeSymbolPicker.suggestedSymbol(for: "git status") == "arrow.triangle.branch")
        #expect(RecipeSymbolPicker.suggestedSymbol(for: "FOO=1 npm run dev") == "shippingbox.fill")
        #expect(RecipeSymbolPicker.suggestedSymbol(for: "htop") == "terminal")
    }
}
