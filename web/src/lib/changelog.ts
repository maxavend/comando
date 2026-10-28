import { readFileSync } from "node:fs"
import { resolve } from "node:path"

export type Item = { html: string; children: string[] }
export type Entry = { version: string; date: string; iso: string; items: Item[] }

const months: Record<string, number> = {
  enero: 1, febrero: 2, marzo: 3, abril: 4, mayo: 5, junio: 6,
  julio: 7, agosto: 8, septiembre: 9, octubre: 10, noviembre: 11, diciembre: 12,
}

const escape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

// Inline Markdown as the CHANGELOG uses it: `code`, **bold** and links.
const inline = (text: string) =>
  escape(text)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a class="underline decoration-border underline-offset-4 hover:decoration-primary" href="$2">$1</a>')

// Reads the repo's CHANGELOG.md, newest version first.
export function changelog(): Entry[] {
  const md = readFileSync(resolve(process.cwd(), "../CHANGELOG.md"), "utf8")
  return md.split(/^## /m).slice(1).map((block) => {
    const [head, ...lines] = block.trim().split("\n")
    const [, version, date] = head.match(/^(\S+)\s*\((.+)\)/)!
    const [, day, month, year] = date.match(/(\d+) de (\w+) de (\d+)/)!
    const iso = `${year}-${String(months[month]).padStart(2, "0")}-${day.padStart(2, "0")}`
    const items: Item[] = []
    for (const line of lines) {
      const m = line.match(/^(\s*)- (.+)$/)
      if (!m) continue
      if (m[1].length >= 2 && items.length) items[items.length - 1].children.push(inline(m[2]))
      else items.push({ html: inline(m[2]), children: [] })
    }
    return { version, date, iso, items }
  })
}
