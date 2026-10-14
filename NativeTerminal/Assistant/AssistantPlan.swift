import FoundationModels

/// What the on-device model may choose. It only classifies the request and
/// fills in details; the app builds the exact command from the choice.
@Generable
enum AssistantAction: String, CaseIterable {
    case runScript, installDependencies, compressAudio, compressVideo, resizeImage, zipFiles
    case gitPublish, gitStatus, installTool, unknown
}

@Generable
struct AssistantStep {
    @Guide(description: """
    La acción. runScript: ejecutar un script de SCRIPTS (servidor, tests, build). \
    installDependencies: instalar las dependencias del proyecto. \
    compressAudio: comprimir o convertir un audio. compressVideo: comprimir un video. \
    resizeImage: cambiar el tamaño de una imagen. zipFiles: comprimir archivos o carpetas en .zip. \
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
}

@Generable
struct AssistantPlan {
    @Guide(description: "Los pasos, en orden. Usa un solo paso salvo que el pedido pida varias cosas.", .count(1...3))
    var steps: [AssistantStep]
}
