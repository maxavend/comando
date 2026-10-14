# NativeTerminal

Una terminal para macOS que funciona como un chat: cada comando es un mensaje y su resultado llega como respuesta.

## Requisitos

- macOS 27 o posterior.
- Apple Intelligence activado, para el asistente (opcional).
- Para compilar: Xcode 27 y [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Qué incluye

- **Chat de comandos.** Usa tu zsh y tu `~/.zshrc`. Muestra colores ANSI, enlaces a archivos y sitios web, barras de progreso y salidas largas plegadas.
- **Programas interactivos.** `vim`, `top`, `ssh` y los REPL se abren en una terminal integrada dentro del chat.
- **Asistente con Apple Intelligence.** Escribe lo que quieres con tus palabras y te propone el comando o la receta, o una herramienta para instalar. Todo corre en tu Mac y nada se ejecuta sin tu clic.
- **Seguridad.** Pide confirmación antes de comandos riesgosos y ofrece mover a la Papelera en vez de usar `rm`.
- **Recetas (⌘K).** Tareas comunes explicadas en lenguaje simple.
- **Herramientas (⇧⌘I).** Todo lo que instalaste con Homebrew, npm (de cada versión de Node), pipx y uv, con actualizaciones y opción de desinstalar.
- **Sesiones.** Se guardan en la barra lateral, con su historial, su carpeta, un emoji y un color.

## Compilar

```bash
xcodegen generate
xcodebuild -scheme NativeTerminal -configuration Release build
```

## Pruebas

```bash
# Unitarias e integración (no mueven el mouse)
xcodebuild -scheme NativeTerminal test

# De interfaz (mueven el mouse; macOS pide autorización)
xcodebuild -scheme NativeTerminalUI test
```

## Atajos

| Atajo | Acción |
| --- | --- |
| ⌘T | Nueva sesión |
| ⌘K | Recetas |
| ⇧⌘I | Herramientas instaladas |
| ⌘. | Detener el comando |
| ⌘↑ | Subir un nivel de carpeta |
| ⇧⌘G | Ir a una carpeta |
| Tab | Completar |
