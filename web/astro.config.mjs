// @ts-check

import tailwindcss from "@tailwindcss/vite"
import { defineConfig } from "astro/config"
import react from "@astrojs/react"

// https://astro.build/config
export default defineConfig({
  // Published on GitHub Pages as a project site.
  site: "https://maxavend.github.io",
  base: "/comando",
  server: { port: 4390, host: "127.0.0.1" },
  vite: {
    plugins: [tailwindcss()],
  },
  integrations: [react()],
})
