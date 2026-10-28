// Paths and links shared by every page. The site lives under a base path on
// Cloudflare Pages, so internal links go through `url()`.
export const repo = "https://github.com/maxavend/comando"
export const releasesUrl = `${repo}/releases/latest`

const base = import.meta.env.BASE_URL.replace(/\/$/, "")

export const url = (path = "") => `${base}/${path.replace(/^\//, "")}`

export const pages = [
  { href: "instalar/", label: "Instalar" },
  { href: "novedades/", label: "Novedades" },
  { href: "atajos/", label: "Atajos" },
  { href: "privacidad/", label: "Privacidad" },
] as const
