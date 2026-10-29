namespace Comando.Core.Assistant;

/// <summary>One point of a guide answer: a glyph, a short title and a line about it.</summary>
/// <param name="Glyph">A Segoe Fluent Icons glyph.</param>
public sealed record GuideItem(string Glyph, string Title, string Detail);

public enum GuideTopic
{
    Overview,
    Assistant,
    Commands,
    Folders,
    Sessions,
    Tools,
    Shortcuts,
    Privacy,
}

/// <summary>A guide answer: an introduction, its points and the next questions worth asking.</summary>
public sealed record GuideAnswer(GuideTopic Topic, string Intro, IReadOnlyList<GuideItem> Items, IReadOnlyList<string> FollowUps);

/// <summary>
/// Questions about Comando itself (“¿qué hace?”, “¿para qué sirve?”,
/// “¿cómo cambio de carpeta?”), answered from a written guide: instant, the
/// same every time, and always true to what the app does.
/// </summary>
public static class AppGuide
{
    // Recognizing a question about the app

    /// <summary>Phrases that ask about something rather than ask for something.</summary>
    private static readonly string[] AskPhrases =
    [
        "para que sirve", "para que sirves", "para que es", "para que son", "cual es el proposito", "cual es tu proposito", "cual es su proposito",
        "que puedes hacer", "que puede hacer", "que se puede hacer", "que sabes hacer", "que haces", "que hace",
        "en que me ayudas", "en que me puedes ayudar", "como funciona", "como funcionas", "como se usa", "como lo uso",
        "como te uso", "como uso", "como empiezo", "por donde empiezo", "quien eres", "que eres", "que es esto",
        "que es", "como hago para", "como puedo", "como", "donde", "hay", "tiene", "tienes", "explicame", "ensename",
        "proposito", "objetivo", "instrucciones", "tutorial", "guia", "manual", "ayuda", "ayudame",
        "help", "es", "son",
    ];

    /// <summary>Words that name the app.</summary>
    private static readonly HashSet<string> AppWords =
    [
        "comando", "app", "aplicacion", "programa", "terminal", "esto", "esta", "este", "aqui", "tu", "usted", "sirve",
    ];

    /// <summary>
    /// Words that can sit around the question without asking about anything
    /// else: greetings, articles, and verbs that go with the topics.
    /// </summary>
    private static readonly HashSet<string> Filler =
    [
        "hola", "holi", "buenas", "hey", "oye", "y", "o", "a", "de", "del", "en", "el", "la", "los", "las", "lo", "un", "una",
        "unos", "unas", "me", "te", "se", "mi", "mis", "su", "sus", "que", "cual", "cuales", "para", "por", "con", "entre",
        "bien", "exactamente", "realmente", "bueno", "porfa", "favor", "puedo", "puedes", "hacer", "hago",
        "uso", "usar", "usas", "usa", "funciona", "cambio", "cambiar", "muevo", "mover", "moverme", "ir", "voy", "abro",
        "abrir", "creo", "crear", "nueva", "nuevo", "nuevas", "otra", "otro", "otras", "veo", "ver", "gestiono", "gestionar",
        "administro", "administrar", "instalo", "instalar", "instaladas", "instalados", "actualizo", "actualizar", "escribo",
        "escribir", "ejecuto", "ejecutar", "corro", "correr", "son", "es", "esta", "estan", "algun", "alguna", "todos",
        "todas", "cosas", "le", "les", "pido", "pedir", "pedirle", "funcionan", "datos", "envia", "manda", "sale",
        "salen", "va", "van", "hay", "tiene", "tienes", "cuantas", "cuantos", "sirven", "rapidos", "rapido",
    ];

    private static readonly Dictionary<GuideTopic, HashSet<string>> TopicWords = new()
    {
        [GuideTopic.Assistant] = ["asistente", "inteligencia", "ia", "ai", "modelo", "phi", "silica", "copilot", "pedidos"],
        [GuideTopic.Commands] = ["comandos", "historial", "detener", "interactivo", "interactivos", "vim", "recetas"],
        [GuideTopic.Folders] = ["carpeta", "carpetas", "directorio", "directorios", "explorador", "cd"],
        [GuideTopic.Sessions] = ["sesion", "sesiones", "pestana", "pestanas", "chats", "conversaciones"],
        [GuideTopic.Tools] = ["herramientas", "paquetes", "gestor", "winget", "scoop"],
        [GuideTopic.Shortcuts] = ["atajo", "atajos", "teclado", "teclas", "shortcuts", "shortcut"],
        [GuideTopic.Privacy] = ["privacidad", "privado", "privada", "seguro", "segura", "seguridad", "internet", "nube", "riesgo"],
    };

    private static readonly HashSet<string> Articles = ["de", "del", "el", "la", "los", "las"];

    private static bool IsTopicWord(string word) => TopicWords.Values.Any(words => words.Contains(word));

    /// <summary>
    /// The topic a request asks about, or null when it asks for something else
    /// (“¿para qué sirve git?”, “instala ffmpeg”).
    /// </summary>
    public static GuideTopic? TopicFor(string request)
    {
        var text = " " + string.Join(' ', TextNormalizer.LettersAndDigits(request).Split(' ', StringSplitOptions.RemoveEmptyEntries)) + " ";
        var asks = false;
        foreach (var phrase in AskPhrases)
        {
            var key = $" {phrase} ";
            if (!text.Contains(key)) continue;
            text = text.Replace(key, " ");
            asks = true;
        }
        var rest = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        // A lone topic word works too: “atajos”, “sesiones”.
        var found = Enum.GetValues<GuideTopic>()
            .Where(topic => TopicWords.TryGetValue(topic, out var words) && rest.Any(words.Contains))
            .ToList();
        var known = rest.All(word => AppWords.Contains(word) || Filler.Contains(word) || IsTopicWord(word));
        // Without a question, only topic names: “atajos de teclado”, not “nueva sesión”.
        var onlyNames = rest.All(word => Articles.Contains(word) || IsTopicWord(word));
        if (!known || !(asks || (onlyNames && found.Count > 0))) return null;
        // “Comando” on its own, or nothing at all, is the app.
        if (found.Count == 0) return asks ? GuideTopic.Overview : null;
        // The most specific one, when a request names several.
        if (found.Count == 1) return found[0];
        return found.Where(topic => topic is not GuideTopic.Tools and not GuideTopic.Commands).Select(topic => (GuideTopic?)topic).FirstOrDefault() ?? found[0];
    }

    /// <summary>Single words that open the guide: “ayuda”, “tutorial”.</summary>
    public static bool IsGuideWord(string word)
    {
        string[] words = ["ayuda", "ayudame", "tutorial", "instrucciones", "guia", "manual", "help", "atajos", "proposito"];
        return words.Contains(TextNormalizer.LettersAndDigits(word).Trim());
    }

    // Answers

    public static GuideAnswer Answer(GuideTopic topic)
    {
        var (intro, items) = Content(topic);
        return new GuideAnswer(topic, intro, items, FollowUps(topic));
    }

    private static readonly (GuideTopic Topic, string Question)[] Questions =
    [
        (GuideTopic.Overview, "¿Qué puede hacer Comando?"),
        (GuideTopic.Assistant, "¿Cómo funciona el asistente?"),
        (GuideTopic.Folders, "¿Cómo cambio de carpeta?"),
        (GuideTopic.Shortcuts, "¿Qué atajos hay?"),
        (GuideTopic.Privacy, "¿Es privado?"),
        (GuideTopic.Sessions, "¿Para qué son las sesiones?"),
        (GuideTopic.Tools, "¿Cómo gestiono mis herramientas?"),
        (GuideTopic.Commands, "¿Cómo escribo comandos?"),
    ];

    /// <summary>The next questions worth asking after <paramref name="topic"/>.</summary>
    public static IReadOnlyList<string> FollowUps(GuideTopic topic) =>
        Questions.Where(question => question.Topic != topic).Take(4).Select(question => question.Question).ToList();

    private static GuideItem Item(string glyph, string title, string detail) => new(glyph, title, detail);

    public static (string Intro, IReadOnlyList<GuideItem> Items) Content(GuideTopic topic) => topic switch
    {
        GuideTopic.Overview => ("Comando es una terminal con forma de chat: escribes un comando, o lo que quieres hacer en tus palabras, y la respuesta llega como un mensaje.",
        new GuideItem[]
        {
            Item("\uE756", "Escribe comandos", "Como en cualquier terminal, con tu PowerShell y tu perfil: Get-ChildItem, git status, npm run dev."),
            Item("\uE945", "Pide en tus palabras", "«Comprime esta carpeta» o «sube mis cambios»: el asistente te propone el comando y tú decides si se ejecuta."),
            Item("\uE838", "Muévete entre carpetas", "Escribe cd como siempre. Arriba del chat ves dónde estás y puedes abrir la carpeta en el Explorador de archivos."),
            Item("\uE8F4", "Trabaja en varias sesiones", "Cada sesión es un PowerShell aparte, con su carpeta y su historial. Ctrl+N abre una nueva."),
            Item("\uE7B8", "Ordena tus herramientas", "Ctrl+Shift+I muestra lo que instalaste con winget, Scoop, npm, pipx y uv, para actualizarlo o quitarlo."),
        }),
        GuideTopic.Assistant => ("El asistente usa Phi Silica, el modelo de Windows que corre aquí en tu PC, para convertir lo que pides en comandos. Está en los PC Copilot+.",
        new GuideItem[]
        {
            Item("\uE8BD", "Escribe con tus palabras", "Si lo que escribes no es un comando, va al asistente en vez de a PowerShell."),
            Item("\uE8FB", "Tú decides", "Te muestra el comando y qué hace. Nada se ejecuta hasta que presionas Ejecutar, y puedes editarlo antes."),
            Item("\uE723", "Adjunta archivos", "Arrastra un archivo a la ventana y pide qué hacer con él: comprimirlo, moverlo, renombrarlo."),
            Item("\uE7B8", "Te sugiere herramientas", "Si hace falta un programa, te cuenta qué hace y lo instala con winget."),
            Item("\uE897", "Fuerza el asistente", "Si tu pedido empieza con el nombre de un programa, ponle ? al inicio."),
        }),
        GuideTopic.Commands => ("Escribe cualquier comando de PowerShell, igual que en Terminal de Windows: Comando carga tu perfil de siempre.",
        new GuideItem[]
        {
            Item("\uE751", "Envía y sigue", "Entrar envía el comando; Mayús+Entrar agrega una línea."),
            Item("\uE71A", "Detén lo que corre", "Ctrl+C, o el botón Detener, interrumpe el comando que está trabajando."),
            Item("\uE946", "Entiende un comando", "Haz clic derecho sobre tu mensaje para ver qué hace cada parte."),
            Item("\uE7F4", "Programas interactivos", "vim, ssh o python se abren como una terminal dentro del chat; al salir vuelves a la conversación."),
            Item("\uE8A4", "Recetas", "Ctrl+K abre tareas comunes y las tuyas, explicadas en español."),
        }),
        GuideTopic.Folders => ("Cada sesión trabaja en una carpeta, y arriba del chat te dice en cuál estás.",
        new GuideItem[]
        {
            Item("\uE838", "Abre la carpeta", "El botón de carpeta, arriba del chat, la muestra en el Explorador de archivos."),
            Item("\uE74A", "Sube un nivel", "Escribe cd .. para ir a la carpeta que contiene la actual."),
            Item("\uE80F", "Lugares de siempre", "cd ~ te lleva a tu carpeta personal; cd ~\\Desktop, al Escritorio."),
            Item("\uE8B7", "Cualquier carpeta", "Escribe cd y la ruta, como C:\\Proyectos. Tab te ayuda a completarla."),
        }),
        GuideTopic.Sessions => ("Las sesiones son como conversaciones separadas: cada una tiene su propio PowerShell, carpeta e historial.",
        new GuideItem[]
        {
            Item("\uE710", "Abre una nueva", "Ctrl+N abre una sesión nueva en la misma carpeta."),
            Item("\uE8A0", "Cambia entre ellas", "Elígela en la barra lateral, o usa Ctrl+Tab y Ctrl+Mayús+Tab."),
            Item("\uE790", "Personalízala", "Haz clic derecho en la barra lateral para cambiarle nombre, emoji o color, o para fijarla arriba."),
            Item("\uE81C", "Quedan guardadas", "Al volver a abrir Comando, cada sesión sigue en su carpeta con su historial."),
        }),
        GuideTopic.Tools => ("Herramientas (Ctrl+Shift+I) junta en un lugar lo que tienes de winget, Scoop, npm, pipx y uv.",
        new GuideItem[]
        {
            Item("\uE777", "Actualiza", "Ve qué está desactualizado y actualízalo con un clic."),
            Item("\uEDA2", "Revisa lo instalado", "Mira qué tienes y con qué gestor lo instalaste."),
            Item("\uE74D", "Desinstala", "Quita lo que ya no usas, sin recordar el comando."),
            Item("\uE734", "Descubre", "Recomendadas te muestra herramientas útiles, explicadas en español."),
        }),
        GuideTopic.Shortcuts => ("Los atajos más útiles de Comando:",
        new GuideItem[]
        {
            Item("\uE710", "Ctrl+N", "Nueva sesión."),
            Item("\uE8A4", "Ctrl+K", "Recetas: tareas comunes y las que guardaste."),
            Item("\uE721", "Ctrl+F", "Buscar en las sesiones."),
            Item("\uE894", "Ctrl+L", "Borrar el historial de la sesión."),
            Item("\uE8A0", "Ctrl+Tab", "Cambiar de sesión (Ctrl+Mayús+Tab, hacia atrás)."),
            Item("\uE7B8", "Ctrl+Mayús+I", "Herramientas instaladas."),
            Item("\uE713", "Ctrl+,", "Ajustes."),
            Item("\uE71A", "Ctrl+C", "Detener el comando que corre, si no hay texto seleccionado."),
        }),
        _ => ("Lo que le pides al asistente se procesa en este PC, con el modelo de Windows.",
        new GuideItem[]
        {
            Item("\uE72E", "Queda en tu PC", "Tus pedidos, archivos y comandos no se envían a ningún servidor."),
            Item("\uE721", "Solo palabras de búsqueda", "Para sugerirte herramientas, consulta winget y npm con palabras clave, nada más."),
            Item("\uE8FB", "Nada sin tu clic", "El asistente nunca ejecuta solo y, para borrar, usa la Papelera de reciclaje."),
            Item("\uE7BA", "Te avisa", "Si un comando que escribes puede borrar o cambiar mucho, te lo advierte antes."),
        }),
    };
}
