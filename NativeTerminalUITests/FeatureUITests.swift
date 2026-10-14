import XCTest

/// Drives the real app with clicks and typing to check each feature end to end.
@MainActor
final class FeatureUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL!

    override func setUp() async throws {
        continueAfterFailure = true
        folder = FileManager.default.temporaryDirectory.appending(path: "nt-ui-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: folder.appending(path: "Carpeta Uno"), withIntermediateDirectories: true)
        try "hola".write(to: folder.appending(path: "notas.txt"), atomically: true, encoding: .utf8)
        try "borrar".write(to: folder.appending(path: "borrar-me.txt"), atomically: true, encoding: .utf8)

        app = XCUIApplication()
        app.launchEnvironment["NATIVETERM_STORE"] = "UITests-\(UUID().uuidString)"
        app.launchEnvironment["NATIVETERM_SKIP_WELCOME"] = "1"
        app.launch()
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "El campo de comando no apareció")
        run("cd \(folder.path(percentEncoded: false))")
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private var composer: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "composer").firstMatch
    }

    private func run(_ command: String, wait: TimeInterval = 1.5) {
        composer.click()
        composer.typeText(command + "\n")
        Thread.sleep(forTimeInterval: wait)
    }

    private func text(_ label: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", label, label)).firstMatch
    }

    // MARK: - 3. Explicación por partes

    func testExplainCommand() {
        run("ls -lhG")
        let description = app.descendants(matching: .any).matching(identifier: "commandDescription").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5), "No aparece la descripción bajo el comando")
        description.click()
        XCTAssertTrue(text("¿Qué hace este comando?").waitForExistence(timeout: 3), "El popover de explicación no se abrió")
        XCTAssertTrue(text("en detalle").exists, "La explicación no incluye las opciones")
        attach("explicacion")
    }

    // MARK: - 4. Papelera

    func testRmOffersTrash() {
        run("rm borrar-me.txt", wait: 1)
        let trash = app.buttons["Mover a la Papelera"]
        XCTAssertTrue(trash.waitForExistence(timeout: 3), "No apareció la opción Mover a la Papelera")
        attach("papelera-alerta")
        trash.click()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "borrar-me.txt").path(percentEncoded: false)),
                       "El archivo sigue en su lugar")
        XCTAssertTrue(text("trash").exists, "No se ve el comando trash en el chat")
    }

    // MARK: - 5. Git

    func testGitMenu() {
        run("git init -q && git checkout -q -b prueba", wait: 2.5)
        run("echo cambio > nuevo.txt", wait: 2.5)
        let git = app.descendants(matching: .any).matching(identifier: "gitMenu").firstMatch
        XCTAssertTrue(git.waitForExistence(timeout: 5), "No aparece la rama de Git en la barra")
        XCTAssertTrue((git.label + (git.value as? String ?? "")).contains("prueba"), "La barra no muestra la rama: \(git.label)")
        git.click()
        let status = app.menuItems["Ver los cambios"]
        XCTAssertTrue(status.waitForExistence(timeout: 3), "El menú de Git no se abrió")
        attach("git-menu")
        status.click()
        XCTAssertTrue(text("nuevo.txt").waitForExistence(timeout: 5), "git status no mostró el archivo nuevo")
    }

    // MARK: - 6. Progreso

    func testProgressBar() {
        run(#"for i in $(seq 0 5 100); do printf "\rDescargando [%d%%]" $i; sleep 0.2; done; echo"#, wait: 2)
        XCTAssertTrue(app.progressIndicators.firstMatch.waitForExistence(timeout: 3), "No apareció la barra de progreso nativa")
        attach("progreso")
    }

    // MARK: - 7. Salidas largas

    func testFoldAndSearch() {
        run("seq 1 80", wait: 2)
        let expand = app.buttons["Mostrar 70 líneas anteriores"]
        XCTAssertTrue(expand.waitForExistence(timeout: 3), "La salida larga no se plegó")
        expand.click()
        XCTAssertTrue(app.buttons["Mostrar menos"].waitForExistence(timeout: 2), "No se desplegó la salida")
        app.buttons["Buscar…"].firstMatch.click()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 3) || app.textFields["Buscar"].exists,
                      "La hoja no abrió con la barra de búsqueda")
        attach("buscar-en-salida")
        app.buttons["Listo"].firstMatch.click()
    }

    // MARK: - 1 y 8. Barra lateral: procesos y personalizar

    func testSidebarProcessAndPinning() {
        run("sleep 40", wait: 1)
        app.typeKey("t", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(text("Ejecutando: sleep 40").waitForExistence(timeout: 5), "La barra lateral no muestra el proceso activo")
        let stop = app.buttons["Detener"].firstMatch
        XCTAssertTrue(stop.exists, "No está el botón Detener en la barra lateral")
        attach("sidebar-proceso")
        stop.click()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(text("Ejecutando: sleep 40").exists, "El proceso no se detuvo desde la barra lateral")

        let row = app.outlines.firstMatch.cells.element(boundBy: 1)
        row.rightClick()
        app.menuItems["Fijar arriba"].click()
        XCTAssertTrue(text("Fijadas").waitForExistence(timeout: 3), "No aparece la sección Fijadas")
        let pinned = app.outlines.firstMatch.cells.element(boundBy: 1)
        pinned.rightClick()
        app.menuItems["Personalizar…"].click()
        XCTAssertTrue(app.buttons["🚀"].waitForExistence(timeout: 3), "No se abrió el editor de sesión")
        app.buttons["🚀"].click()
        attach("personalizar")
        app.buttons["Listo"].click()
    }

    // MARK: - 2. Recetas

    func testRecipes() {
        app.typeKey("k", modifierFlags: .command)
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'Qué quieres hacer'")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3), "⌘K no abrió las recetas")
        search.typeText("puerto\n")
        let port = app.textFields["Puerto"].firstMatch
        XCTAssertTrue(port.waitForExistence(timeout: 3), "No se abrió el formulario de la receta")
        port.click()
        port.typeText("6006")
        XCTAssertTrue(text("lsof -nP -iTCP:6006").exists, "La vista previa no refleja el puerto")
        attach("receta")
        app.buttons["Ejecutar"].click()
        XCTAssertTrue(text("lsof -nP -iTCP:6006").waitForExistence(timeout: 5), "La receta no se ejecutó en el chat")
    }

    // MARK: - Archivos clicables

    func testClickableFiles() {
        run("ls", wait: 2)
        let link = app.links["notas.txt"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 3), "Los nombres de archivo no son enlaces")
        link.click()
        Thread.sleep(forTimeInterval: 1.5)
        attach("vista-rapida")
        let folderLink = app.links["Carpeta Uno"].firstMatch
        if folderLink.exists {
            app.typeKey(.escape, modifierFlags: [])
            folderLink.click()
            XCTAssertTrue(text("Ahora estás en").waitForExistence(timeout: 5), "Clic en carpeta no navegó")
        }
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
