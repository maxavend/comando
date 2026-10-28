<p align="center">
  <img src="docs/images/icono.png" width="128" height="128" alt="Ícono de Comando">
</p>

<h1 align="center">Comando</h1>

<p align="center">
  Una terminal para macOS que funciona como un chat: cada comando es un mensaje y su resultado llega como respuesta.<br>
  Y si no sabes el comando, pídelo con tus palabras.
</p>

<p align="center">
  <a href="https://github.com/maxavend/comando/releases/latest"><img src="https://img.shields.io/github/v/release/maxavend/comando?label=versi%C3%B3n" alt="Última versión"></a>
  <img src="https://img.shields.io/badge/macOS-27-black?logo=apple" alt="macOS 27">
  <img src="https://img.shields.io/badge/SwiftUI-Liquid%20Glass-blue?logo=swift&logoColor=white" alt="SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/maxavend/comando?label=licencia" alt="Licencia MIT"></a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/chat-oscuro.png">
    <img src="docs/images/chat-claro.png" alt="Comando con un pedido al asistente para comprimir un audio y, en la barra lateral, otra sesión con un servidor en marcha">
  </picture>
</p>

## Requisitos

- macOS 27 o posterior.
- Apple Intelligence activado, para el asistente (opcional).
- Para compilar: Xcode 27 y [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Instalar

1. Descarga `Comando-<versión>.dmg` desde [Releases](https://github.com/maxavend/comando/releases).
2. Abre el `.dmg` y arrastra Comando a Aplicaciones.
3. La app no está notarizada por Apple, así que la primera vez macOS la bloquea. Ábrela una vez, ve a **Ajustes del Sistema → Privacidad y seguridad** y presiona **Abrir de todos modos**.

## Qué incluye

- **Chat de comandos.** Usa tu zsh y tu `~/.zshrc`. Muestra colores ANSI, enlaces a archivos y sitios web, barras de progreso y salidas largas plegadas.
- **Programas interactivos.** `vim`, `top`, `ssh` y los REPL se abren en una terminal integrada dentro del chat.
- **Asistente con Apple Intelligence.** Conversa contigo en tus palabras y recuerda lo que hablaron: te propone el comando, explica qué hace, aconseja herramientas y renombra muchos archivos de una vez sin pisar ninguno. Todo corre en tu Mac y nada se ejecuta sin tu clic.
- **Agentes de IA como chat.** Escribe `agy`, `claude`, `codex` o `qwen` y sus respuestas llegan en burbujas, con sus herramientas como tarjetas y sus permisos como botones. Su pantalla original queda a un clic.
- **Seguridad.** Pide confirmación antes de comandos riesgosos o de cambiar muchos archivos de una vez, mostrando qué cambia, y ofrece mover a la Papelera en vez de usar `rm`.
- **Recetas (⌘K).** Tareas comunes explicadas en lenguaje simple.
- **Herramientas (⇧⌘I).** Todo lo que instalaste con Homebrew, npm (de cada versión de Node), pipx y uv, con actualizaciones y opción de desinstalar.
- **Guía.** Pregúntale al asistente “¿qué hace?”, “¿cómo cambio de carpeta?” o “¿qué atajos hay?”.
- **Carpetas.** El botón de carpeta, arriba a la izquierda, te lleva a otra o la abre en Finder; sobre los mensajes queda dicho dónde corrió cada uno.
- **Sesiones.** Se guardan en la barra lateral, con su historial, su carpeta, un emoji y un color.

## Pregúntale qué hace

El asistente también es la guía de la app: “¿para qué sirve?”, “¿cómo cambio de carpeta?”, “¿qué atajos hay?” o “¿es privado?” responden al instante, aunque Apple Intelligence no esté activado.

<p align="center">
  <img src="docs/images/guia.png" width="800" alt="La guía de Comando respondiendo “¿Para qué sirve?”">
</p>

## Privacidad

- Lo que le pides al asistente se procesa en tu Mac con Apple Intelligence.
- Para sugerirte herramientas, Comando solo consulta Homebrew, npm y tldr con palabras clave; tus archivos y comandos no salen del Mac.
- El asistente nunca ejecuta nada sin tu clic, no propone `sudo` y, para borrar, usa la Papelera.

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
| ⇧⌘] / ⇧⌘[ | Sesión siguiente / anterior |
| ⇧⌘K | Limpiar historial |
| Tab | Completar |

## Sitio web

El sitio vive en [`web/`](web): Astro, con React y [shadcn/ui](https://ui.shadcn.com) en las partes interactivas (el menú del teléfono, el visor de capturas y la lista de momentos). Novedades sale de este CHANGELOG y el botón de descarga apunta al último `.dmg`, los dos al construir. Al subir cambios a `main` o publicar una versión, Cloudflare Pages publica los cambios de `main` en comando.maxavend.com.

```bash
cd web
npm install
npm run dev
```

## Contribuir

¿Encontraste un error o tienes una idea? [Abre un issue](https://github.com/maxavend/comando/issues/new/choose). Los cambios de cada versión están en el [CHANGELOG](CHANGELOG.md).

## Licencia

[MIT](LICENSE) © 2026 Maximiliano Avendaño ([@maxavend](https://github.com/maxavend)). Incluye una copia de [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT) en `Vendor/SwiftTerm`.
