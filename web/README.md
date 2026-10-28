# Sitio de Comando

Astro + React + shadcn/ui (estilo base-nova, Base UI) + Tailwind 4.

- `src/pages/`: la portada y las páginas Instalar, Novedades, Atajos y Privacidad.
- `src/styles/global.css`: los tokens (papel, tinta, el azul del ícono, vidrio) que alimentan el tema de shadcn, en claro y oscuro.
- `src/components/`: el encabezado, el pie y las islas de React (`mobile-menu`, `shot`, `moments`). `ui/` son los componentes de shadcn.
- `src/lib/`: la última versión desde GitHub y el CHANGELOG, leídos al construir.

```bash
npm run dev        # http://127.0.0.1:4390/ (publicado en comando.maxavend.com)
npm run build      # genera dist/
npm run typecheck
```
