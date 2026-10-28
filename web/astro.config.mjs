// @ts-check

import tailwindcss from "@tailwindcss/vite"
import { defineConfig } from "astro/config"
import react from "@astrojs/react"

// https://astro.build/config
export default defineConfig({
  // Published on Cloudflare Pages at the product subdomain.
  site: "https://comando.maxavend.com",
  base: "/",
  server: { port: 4390, host: "127.0.0.1" },
  vite: {
    plugins: [tailwindcss()],
  },
  integrations: [react()],
})
