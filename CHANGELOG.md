# Cambios

## 1.3.1 (15 de octubre de 2026)

- “Acerca de Comando” indica la licencia MIT.

## 1.3 (15 de octubre de 2026)

- La bienvenida y la pantalla de inicio muestran la burbuja del ícono de Comando.
- La bienvenida explica que puedes presionar “Estás en…” para cambiar de carpeta o abrirla en Finder.
- “Acerca de Comando” incluye la firma maxavend.

## 1.2 (15 de octubre de 2026)

- Guía integrada: pregúntale al asistente “¿qué hace?”, “¿para qué sirve?”, “¿cómo cambio de carpeta?”, “¿qué atajos hay?” o “¿es privado?” y responde al instante con un mini tutorial, aunque Apple Intelligence no esté activado.
- “Estás en…” y “Ahora estás en…” abren un menú para ir a otra carpeta, volver a una anterior o mostrarla en Finder.
- El asistente responde con sus propias palabras, en vez de frases fijas.
- Las sugerencias del asistente van debajo de la burbuja, como respuestas rápidas.
- Botones en cápsula y de tamaño regular, más fáciles de presionar.
- La burbuja de los pedidos cambia suavemente de color al hacer scroll.
- Cada sesión tiene un ícono según su carpeta: casa, Escritorio, Descargas, proyecto Swift, Node, Python, Git…

## 1.1 (15 de octubre de 2026)

- El asistente busca herramientas de terminal en Homebrew, npm y tldr, propone el comando con ejemplos reales y dice en español qué hace cada herramienta.
- Chat al estilo Messages:
  - Burbujas más redondas y letra más grande.
  - Fecha y carpeta por separado, y el estado solo cuando aporta.
- Liquid Glass: los mensajes pasan bajo la barra y el campo de texto, y el encabezado flotante muestra la sesión.
- Pedidos al asistente:
  - Burbuja de azul a violeta y una estrella como símbolo.
  - Brillo de Apple Intelligence en el campo y estado “pensando” sin burbuja.
- Corrige un cierre al abrir sesiones (SwiftTerm, proceso hijo tras forkpty).

## 1.0.2 (15 de octubre de 2026)

- El asistente conoce lo que tienes instalado:
  - “Abre Antigravity”, “abre el CLI de Antigravity” (`agy`), “abre la configuración del sistema”, “abre notas.md” y “¿tengo ffmpeg?” se responden al instante, aunque escribas el nombre de forma aproximada o en español.
  - Busca también en carpetas dentro de Aplicaciones y reconoce los comandos que instalan apps como VS Code, Cursor, Xcode o Antigravity.
  - Cuando el modelo escribe un comando, recibe las apps y comandos instalados relacionados con el pedido.

## 1.0.1 (15 de octubre de 2026)

- El asistente ya no se queda en “Armando el comando…”:
  - Cada consulta al modelo tiene un tope de largo y de tiempo, y el asistente completo también, así que siempre termina con una respuesta.
  - Las herramientas lentas o sin conexión ya no pueden trabar la app.
- Los pedidos claros (“corre el proyecto”, “sube mis cambios a GitHub”, “comprime este PDF”) se responden al instante sin pasar por el modelo. Las preguntas como “¿para qué sirve git?” se explican.
- Documentos:
  - Convierte documentos de Pages, Word, Keynote y Numbers a PDF con las apps que vienen en el Mac.
  - El nuevo comando `comprimir-pdf` reduce el peso de un PDF con el filtro de macOS.
- La burbuja de “pensando” se ajusta al largo de cada mensaje.
- Prueba de estrés con más de 40 pedidos reales: todos responden en menos de 5 segundos y ninguno propone algo riesgoso.

## 1.0 (14 de octubre de 2026)

Primera versión de Comando.

- Terminal con forma de chat sobre tu zsh: colores, enlaces, barras de progreso, salidas largas plegadas y terminal integrada para programas interactivos.
- Asistente con Apple Intelligence que funciona en tu Mac y entiende pedidos escritos con tus palabras:
  - Saludos, acciones conocidas, recetas y herramientas recomendadas.
  - Comandos escritos por el modelo, revisados antes de mostrarlos.
  - Respuestas a preguntas.
- Seguridad:
  - Pide confirmación antes de cada parte riesgosa de un comando, también dentro de `$(…)` y `bash -c`.
  - Ofrece mover a la Papelera en vez de usar `rm`.
  - Nunca escribe dentro de un programa que está en ejecución.
- Recetas (⌘K) y gestor de herramientas (⇧⌘I) para Homebrew, npm (de cada versión de Node), pipx y uv.
- Sesiones con historial, carpeta, emoji y color, y notificaciones cuando termina un comando largo.
