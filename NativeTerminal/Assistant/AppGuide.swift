import Foundation

/// One point of a guide answer: a symbol, a short title and a line about it.
nonisolated struct GuideItem: Codable, Hashable, Sendable {
    var symbol: String
    var title: String
    var detail: String
}

/// Questions about Comando itself (“¿qué hace?”, “¿para qué sirve?”,
/// “¿cómo cambio de carpeta?”), answered from a written guide: instant, the
/// same every time, and always true to what the app does.
nonisolated enum AppGuide {
    enum Topic: CaseIterable, Sendable {
        case overview, assistant, commands, folders, sessions, tools, shortcuts, privacy
    }

    // MARK: - Recognizing a question about the app

    /// Phrases that ask about something rather than ask for something.
    private static let askPhrases = [
        "para que sirve", "para que sirves", "para que es", "para que son", "cual es el proposito", "cual es tu proposito", "cual es su proposito",
        "que puedes hacer", "que puede hacer", "que se puede hacer", "que sabes hacer", "que haces", "que hace",
        "en que me ayudas", "en que me puedes ayudar", "como funciona", "como funcionas", "como se usa", "como lo uso",
        "como te uso", "como uso", "como empiezo", "por donde empiezo", "quien eres", "que eres", "que es esto",
        "que es", "como hago para", "como puedo", "como", "donde", "hay", "tiene", "tienes", "explicame", "ensename",
        "proposito", "objetivo", "instrucciones", "tutorial", "guia", "manual", "ayuda", "ayudame",
        "help", "es", "son",
    ]
    /// Words that name the app.
    private static let appWords: Set<String> = [
        "comando", "app", "aplicacion", "programa", "terminal", "esto", "esta", "este", "aqui", "tu", "usted", "sirve",
    ]
    /// Words that can sit around the question without asking about anything
    /// else: greetings, articles, and verbs that go with the topics.
    private static let filler: Set<String> = [
        "hola", "holi", "buenas", "hey", "oye", "y", "o", "a", "de", "del", "en", "el", "la", "los", "las", "lo", "un", "una",
        "unos", "unas", "me", "te", "se", "mi", "mis", "su", "sus", "que", "cual", "cuales", "para", "por", "con", "entre",
        "bien", "exactamente", "realmente", "bueno", "porfa", "por favor", "favor", "puedo", "puedes", "hacer", "hago",
        "uso", "usar", "usas", "usa", "funciona", "cambio", "cambiar", "muevo", "mover", "moverme", "ir", "voy", "abro",
        "abrir", "creo", "crear", "nueva", "nuevo", "nuevas", "otra", "otro", "otras", "veo", "ver", "gestiono", "gestionar",
        "administro", "administrar", "instalo", "instalar", "instaladas", "instalados", "actualizo", "actualizar", "escribo",
        "escribir", "ejecuto", "ejecutar", "corro", "correr", "son", "es", "esta", "estan", "algun", "alguna", "todos",
        "todas", "cosas", "le", "les", "pido", "pedir", "pedirle", "funcionan", "datos", "envia", "manda", "sale",
        "salen", "va", "van", "hay", "tiene", "tienes", "cuantas", "cuantos", "sirven", "rapidos", "rapido",
    ]
    private static let topicWords: [Topic: Set<String>] = [
        .assistant: ["asistente", "inteligencia", "apple", "intelligence", "ia", "ai", "modelo", "estrella", "pedidos"],
        .commands: ["comandos", "historial", "detener", "interactivo", "interactivos", "vim", "recetas"],
        .folders: ["carpeta", "carpetas", "directorio", "directorios", "finder", "cd"],
        .sessions: ["sesion", "sesiones", "pestana", "pestanas", "chats", "conversaciones"],
        .tools: ["herramientas", "paquetes", "gestor"],
        .shortcuts: ["atajo", "atajos", "teclado", "teclas", "shortcuts", "shortcut"],
        .privacy: ["privacidad", "privado", "privada", "seguro", "segura", "seguridad", "internet", "nube", "riesgo"],
    ]

    /// The topic a request asks about, or nil when it asks for something else
    /// (“¿para qué sirve git?”, “instala ffmpeg”).
    static func topic(for request: String) -> Topic? {
        var text = " " + AssistantEngine.normalized(request).map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) } + " "
        var asks = false
        for phrase in askPhrases where text.contains(" \(phrase) ") {
            text = text.replacingOccurrences(of: " \(phrase) ", with: " ")
            asks = true
        }
        let rest = text.split(separator: " ").map(String.init)
        // A lone topic word works too: “atajos”, “sesiones”.
        let found = Topic.allCases.filter { topic in rest.contains { topicWords[topic]?.contains($0) ?? false } }
        let known = rest.allSatisfy { word in
            appWords.contains(word) || filler.contains(word) || topicWords.values.contains { $0.contains(word) }
        }
        // Without a question, only topic names: “atajos de teclado”, not “nueva sesión”.
        let onlyNames = rest.allSatisfy { word in
            ["de", "del", "el", "la", "los", "las"].contains(word) || topicWords.values.contains { $0.contains(word) }
        }
        guard known, asks || (onlyNames && !found.isEmpty) else { return nil }
        // “Comando” on its own, or nothing at all, is the app.
        if found.isEmpty { return asks ? .overview : nil }
        // The most specific one, when a request names several.
        return found.count == 1 ? found[0] : found.first { $0 != .tools && $0 != .commands } ?? found[0]
    }

    /// Single words that open the guide: “ayuda”, “tutorial”.
    static func isGuideWord(_ word: String) -> Bool {
        ["ayuda", "ayudame", "tutorial", "instrucciones", "guia", "manual", "help", "atajos", "proposito"]
            .contains(AssistantEngine.normalized(word).trimmingCharacters(in: .punctuationCharacters))
    }

    // MARK: - Answers

    static func reply(for topic: Topic, inventory: ToolInventory) -> AssistantReply {
        let (intro, items) = content(topic)
        var reply = AssistantReply(explanation: intro, proposals: [])
        reply.extras.guide = items
        // The assistant topic ends with real requests to try; the rest with
        // the next questions worth asking.
        reply.extras.examples = topic == .assistant
            ? AssistantEngine.examples(for: inventory)
            : followUps.filter { $0.0 != topic }.prefix(4).map(\.1)
        return reply
    }

    private static let followUps: [(Topic, String)] = [
        (.overview, String(localized: "¿Qué puede hacer Comando?")),
        (.assistant, String(localized: "¿Cómo funciona el asistente?")),
        (.folders, String(localized: "¿Cómo cambio de carpeta?")),
        (.shortcuts, String(localized: "¿Qué atajos hay?")),
        (.privacy, String(localized: "¿Es privado?")),
        (.sessions, String(localized: "¿Para qué son las sesiones?")),
        (.tools, String(localized: "¿Cómo gestiono mis herramientas?")),
        (.commands, String(localized: "¿Cómo escribo comandos?")),
    ]

    private static func item(_ symbol: String, _ title: String.LocalizationValue, _ detail: String.LocalizationValue) -> GuideItem {
        GuideItem(symbol: symbol, title: String(localized: title), detail: String(localized: detail))
    }

    static func content(_ topic: Topic) -> (String, [GuideItem]) {
        switch topic {
        case .overview:
            (String(localized: "Comando es una terminal con forma de chat: escribes un comando, o lo que quieres hacer en tus palabras, y la respuesta llega como un mensaje."), [
                item("apple.terminal", "Escribe comandos", "Como en cualquier terminal, con tu zsh y tu configuración: ls, git status, npm run dev."),
                item("sparkle", "Pide en tus palabras", "«Comprime este video» o «sube mis cambios»: el asistente te propone el comando y tú decides si se ejecuta."),
                item("folder", "Muévete entre carpetas", "Presiona «Estás en…» sobre los mensajes para ir a otra carpeta o abrirla en Finder."),
                item("sidebar.left", "Trabaja en varias sesiones", "Cada sesión es un shell aparte, con su carpeta y su historial. ⌘T abre una nueva."),
                item("shippingbox", "Ordena tus herramientas", "⇧⌘I muestra lo que tienes instalado con Homebrew y npm, para actualizarlo o quitarlo."),
            ])
        case .assistant:
            (String(localized: "El asistente usa Apple Intelligence, aquí en tu Mac, para convertir lo que pides en comandos."), [
                item("text.bubble", "Escribe con tus palabras", "Si lo que escribes no es un comando, el campo se ilumina y la flecha cambia a una estrella: va al asistente."),
                item("hand.tap", "Tú decides", "Te muestra el comando y qué hace. Nada se ejecuta hasta que presionas Ejecutar, y puedes editarlo antes."),
                item("paperclip", "Adjunta archivos", "Arrastra un archivo a la ventana y pide qué hacer con él: comprimirlo, convertirlo, achicarlo."),
                item("shippingbox", "Te sugiere herramientas", "Si hace falta un programa, te cuenta qué hace y lo instala con un clic."),
                item("questionmark", "Fuerza el asistente", "Si tu pedido empieza con el nombre de un programa, ponle ? al inicio."),
            ])
        case .commands:
            (String(localized: "Escribe cualquier comando de zsh, igual que en Terminal: Comando carga tu configuración de siempre."), [
                item("return", "Envía y repite", "↩ envía el comando. ↑ y ↓ recorren los que ya escribiste."),
                item("stop.fill", "Detén lo que corre", "⌘. interrumpe el comando que está trabajando."),
                item("info.circle", "Entiende un comando", "Pasa el mouse sobre tu mensaje para ver qué hace, o haz clic derecho para verlo paso a paso."),
                item("macwindow", "Programas interactivos", "vim, top o ssh se abren como una terminal dentro del chat; al salir vuelves a la conversación."),
                item("wand.and.sparkles", "Recetas", "¿No sabes qué escribir? ⌘K abre tareas comunes listas para usar."),
            ])
        case .folders:
            (String(localized: "Cada sesión trabaja en una carpeta, y sobre los mensajes te dice en cuál estás."), [
                item("folder", "Presiona «Estás en…»", "Abre un menú para ir a otra carpeta, a una reciente o mostrarla en Finder."),
                item("arrow.up", "Sube un nivel", "⌘↑ va a la carpeta que contiene la actual."),
                item("house", "Lugares de siempre", "⇧⌘H Inicio, ⇧⌘D Escritorio, ⇧⌘O Documentos y ⌥⌘L Descargas."),
                item("folder.badge.questionmark", "Cualquier carpeta", "⇧⌘G abre el selector de carpetas. También puedes escribir cd como siempre."),
            ])
        case .sessions:
            (String(localized: "Las sesiones son como conversaciones separadas: cada una tiene su propio shell, carpeta e historial."), [
                item("plus", "Abre una nueva", "⌘T abre una sesión nueva; ⌥⌘T la abre en la misma carpeta."),
                item("sidebar.left", "Cambia entre ellas", "Elígela en la barra lateral, o usa ⇧⌘] y ⇧⌘[."),
                item("paintpalette", "Personalízala", "Presiona el nombre arriba del chat para cambiarle nombre, emoji o color."),
                item("clock.arrow.circlepath", "Quedan guardadas", "Al volver a abrir Comando, cada sesión sigue en su carpeta con su historial."),
            ])
        case .tools:
            (String(localized: "Herramientas instaladas (⇧⌘I) junta en un lugar lo que tienes de Homebrew, npm, pipx y uv."), [
                item("arrow.up.circle", "Actualiza", "Ve qué está desactualizado y actualízalo con un clic."),
                item("internaldrive", "Revisa el espacio", "Mira cuánto ocupa cada herramienta y desde cuándo la tienes."),
                item("trash", "Desinstala", "Quita lo que ya no usas, sin recordar el comando."),
                item("star", "Descubre", "Recomendadas te muestra herramientas útiles, explicadas en español."),
            ])
        case .shortcuts:
            (String(localized: "Los atajos más útiles de Comando:"), [
                item("plus", "⌘T", "Nueva sesión (⌥⌘T, en la misma carpeta)."),
                item("wand.and.sparkles", "⌘K", "Recetas: tareas comunes listas para usar."),
                item("stop.fill", "⌘.", "Detener el comando que corre."),
                item("arrow.up", "⌘↑", "Subir un nivel de carpeta; ⇧⌘G para ir a cualquiera."),
                item("shippingbox", "⇧⌘I", "Herramientas instaladas."),
                item("clear", "⇧⌘K", "Limpiar el historial de la sesión."),
            ])
        case .privacy:
            (String(localized: "Lo que le pides al asistente se procesa en este Mac, con Apple Intelligence."), [
                item("lock", "Queda en tu Mac", "Tus pedidos, archivos y comandos no se envían a ningún servidor."),
                item("magnifyingglass", "Solo palabras de búsqueda", "Para sugerirte herramientas, consulta Homebrew y npm con palabras clave, nada más."),
                item("hand.raised", "Nada sin tu clic", "El asistente nunca ejecuta solo, no propone sudo y, para borrar, usa la Papelera."),
                item("exclamationmark.triangle", "Te avisa", "Si un comando que escribes puede borrar o cambiar mucho, te lo advierte antes."),
            ])
        }
    }
}
