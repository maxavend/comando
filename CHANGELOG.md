# Cambios

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
