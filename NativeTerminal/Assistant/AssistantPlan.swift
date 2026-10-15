import FoundationModels

// The on-device model is small, so each call asks for one focused decision.

/// Known actions: the model only classifies the request and fills in
/// details; the app builds the exact command from the choice.
@Generable
enum AssistantAction: String, CaseIterable {
    case runScript, installDependencies, compressAudio, compressVideo, resizeImage, zipFiles
    case convertToPDF, compressPDF, gitPublish, gitStatus, installTool, unknown
}

@Generable
struct AssistantStep {
    @Guide(description: """
    La acción. runScript: ejecutar un script de SCRIPTS (servidor, tests, build). \
    installDependencies: instalar las dependencias del proyecto. \
    compressAudio: comprimir o convertir un audio. compressVideo: comprimir un video. \
    resizeImage: cambiar el tamaño de una imagen. zipFiles: comprimir archivos o carpetas en .zip. \
    convertToPDF: pasar un documento (Pages, Word, Keynote, Numbers) a PDF. compressPDF: reducir el peso de un PDF. \
    gitPublish: subir o publicar cambios en GitHub. gitStatus: ver qué cambió en el proyecto. \
    installTool: instalar un programa con Homebrew. unknown: ninguna acción sirve.
    """)
    var action: AssistantAction
    @Guide(description: "Para runScript: el nombre exacto de un script de SCRIPTS")
    var script: String?
    @Guide(description: "El archivo o carpeta de ADJUNTOS o ARCHIVOS al que se aplica, escrito igual")
    var file: String?
    @Guide(description: "Para resizeImage: ancho en píxeles")
    var width: Int?
    @Guide(description: "Para gitPublish: mensaje corto del commit, en español")
    var message: String?
    @Guide(description: "Para installTool: nombre del paquete de Homebrew")
    var package: String?
    @Guide(description: "Para convertToPDF: true si además pide que pese poco")
    var compress: Bool?
}

@Generable
struct AssistantPlan {
    @Guide(description: "Los pasos, en orden. Usa un solo paso salvo que el pedido pida varias cosas.", .count(1...3))
    var steps: [AssistantStep]
}

/// Which of a few candidate recipes or tools fits the request.
@Generable
struct OptionChoice {
    @Guide(description: "El número de la opción que cumple el pedido, o 0 si ninguna lo cumple de verdad")
    var option: Int
}

/// A command the model writes when nothing known fits.
@Generable
struct WrittenCommand {
    @Guide(description: "Un solo comando de zsh para macOS, corto y seguro, sin sudo. Usa solo archivos del contexto. Vacío si no sabes uno.")
    var command: String
    @Guide(description: "Qué hace el comando, en una oración corta en español que empiece con un verbo. Ejemplo: Cuenta las líneas del archivo notas.md.")
    var explanation: String
}

/// A second look: does the command really do what was asked?
@Generable
struct CommandCheck {
    @Guide(description: "true solo si el comando hace exactamente lo que pide el pedido")
    var matches: Bool
}
