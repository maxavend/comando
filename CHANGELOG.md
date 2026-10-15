# Cambios

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
