# Cambios

## 1.6.1 (21 de octubre de 2026)

- La guía explica bien cómo cambiar de carpeta: con el botón de carpeta, arriba a la izquierda. Ya no dice que se presione “Estás en…”, que desde la 1.6 es solo texto.

## 1.6 (21 de octubre de 2026)

- La fila de cada sesión es más limpia, como en Mensajes: el punto verde del avatar dice que algo corre, la segunda línea muestra solo el comando y la hora está siempre. Ya no hay botón de detener ni punto de no leído.
- Las salidas largas, mientras corren o ya terminadas, se pliegan a sus últimas 10 filas, también cuando son pocas líneas muy largas. “Ver más” las abre con un resorte, sin saltos, y “Ver todo” abre la salida completa.
- El clic derecho en un comando del chat vuelve a mostrar su menú, con Copiar comando y Guardar como receta. Antes aparecía el menú de texto de macOS.
- Menos controles repetidos: “Estás en…” en el chat es solo texto (la carpeta se cambia con el botón de arriba), el nombre se edita en Personalizar, el menú + solo inserta rutas y Recetas se abre con la varita o ⌘K.
- Más aire bajo los títulos de la barra lateral.

## 1.5 (20 de octubre de 2026)

- Buscador en la barra lateral, en vidrio como el de Mensajes (⌘F). Los resultados vienen por secciones: sesiones, comandos, la línea exacta de una salida, carpetas, tus recetas y las recetas incluidas. Se recorren con ↑ ↓ y se abren con ↩, y al final siempre está “Preguntar a Comando”.
- Mis recetas: clic derecho en un comando del chat › Guardar como receta. Le pones nombre, símbolo y color, eliges qué partes se preguntan al usarla, su grupo y si corre siempre en su carpeta. Aparecen arriba en ⌘K y en la búsqueda, con editar, duplicar, eliminar y arrastrar para ordenar.
- ⌘K se abre como Spotlight: una cápsula de búsqueda y el panel de resultados en vidrio, sobre la ventana oscurecida. Un clic fuera o Esc lo cierran.
- Seleccionar varias sesiones con ⌘-clic o ⇧-clic para archivarlas o eliminarlas juntas. Las archivadas quedan abajo, con su historial; escribir en una la trae de vuelta. ⌃⌘A archiva.
- Carpetas en la barra lateral: agrega las que usas (con el botón o arrastrándolas desde Finder) y cada una agrupa sus sesiones, se pliega con un chevron y tiene un + para abrir una terminal ahí.
- La barra lateral tiene las medidas de Mensajes: avatares más grandes, punto azul de no leído, hasta dos líneas de vista previa y separadores finos.
- El encabezado ordena por jerarquía: la carpeta y la rama a la izquierda, las acciones a la derecha. El avatar ya no crece al pasar el mouse.
- `cal` y otros programas ya no fallan con “setlocale”: la shell usa un idioma instalado en el Mac.

## 1.4.4 (19 de octubre de 2026)

- El editor de la sesión permite elegir un SF Symbol para el avatar, además de un emoji; el primero es el automático según la carpeta.
- El avatar del editor se ve nítido y muestra el ícono de la carpeta.
- El primer color de la paleta es el gris de Mensajes, el mismo del avatar.

## 1.4.3 (19 de octubre de 2026)

- “Terminar” cierra todo lo abierto en la sesión, esté donde esté: la pantalla del programa y la conversación con el agente. “Volver al chat” es lo único que sigue la conversación.
- La barra bajo el encabezado ya no aparece sobre una tarjeta que se ve.
- El botón de enviar es siempre el de siempre; el borde de luz del campo indica cuándo responde Apple Intelligence.

## 1.4.2 (19 de octubre de 2026)

- Bajo el encabezado aparece lo que está abierto en la sesión (un agente en línea o un programa en la terminal), con Ver y Terminar, cuando su tarjeta ya no se ve.
- Cuando un agente necesita la terminal, el chat lo explica con una tarjeta clara y un botón para abrirla.
- Los mensajes cortos, como “¿sigues ahí?”, ya no le cambian el nombre a la sesión.

## 1.4.1 (19 de octubre de 2026)

- Codex y Qwen ya no se quedan esperando en el modo chat: responden o muestran su error en segundos.
- Cuando un agente necesita su propia pantalla (iniciar sesión, actualizarse, confiar en la carpeta o responder una pregunta), Comando abre la terminal solo y explica por qué; al cerrarla, el chat sigue.
- Si un agente no da señales en 45 segundos, también se abre su pantalla en vez de esperar para siempre.

## 1.4 (19 de octubre de 2026)

- Apple Intelligence conversa de verdad:
  - Responde con sus propias palabras, con variedad y a medida que escribe, con negrita, código y listas.
  - Recuerda la conversación de cada sesión: “comprime Entrevista.aiff” y luego “ahora pásalo a mp3” funciona.
  - Explica comandos (“¿qué hace tar?”) y aconseja herramientas mirando tu carpeta, lo que tienes instalado, ejemplos reales y Homebrew.
  - Filtros para que no invente archivos, no diga que ya hizo algo ni sugiera sudo o borrar.
- Renombrar muchos archivos de una vez (“renombra todas las fotos como vacaciones”), numerados y sin reemplazar ninguno.
- Freno para cambios masivos: antes de renombrar o mover muchos archivos aparece una confirmación con la lista de lo que cambia.
- Los agentes de IA (agy, Claude Code, Codex, Qwen) conversan en burbujas:
  - Sus herramientas aparecen como tarjetas y los permisos como botones.
  - “Ver en la terminal” abre su pantalla y “Volver al chat” sigue la conversación.
  - Avisa mientras inicia y cuando está en línea.
- Los CLI de IA abiertos en la terminal se manejan desde el campo de abajo, incluso sus menús, y se cierran con “Terminar”.
- Las sesiones toman un nombre según la conversación.
- Borde de luz de Apple Intelligence en el campo y botón de enviar con sus colores, solo cuando responde ella.
- Encabezado como el de Mensajes: avatar gris de 40 pt con el nombre al tamaño de macOS.
- La bienvenida y la pantalla de inicio muestran la burbuja de Comando como símbolo.

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
