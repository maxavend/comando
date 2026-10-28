import { releasesUrl } from "./site"

export type Release = { href: string; note: string; version: string | null }

let cached: Promise<Release> | undefined

// Asks GitHub for the latest .dmg once per build. Without network or a .dmg,
// the buttons open the releases page instead.
export function latestRelease(): Promise<Release> {
  cached ??= (async () => {
    const fallback = { href: releasesUrl, note: "La versión más reciente, en GitHub.", version: null }
    try {
      const headers: Record<string, string> = { Accept: "application/vnd.github+json" }
      if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`
      const res = await fetch("https://api.github.com/repos/maxavend/comando/releases/latest", { headers })
      if (!res.ok) return fallback
      const release = await res.json()
      const dmg = release.assets?.find((a: { name: string }) => a.name.endsWith(".dmg"))
      if (!dmg) return fallback
      const version = String(release.tag_name).replace(/^v/, "")
      return {
        href: dmg.browser_download_url,
        version,
        note: `Versión ${version}, archivo .dmg de ${Math.round(dmg.size / 1e6)}\u00a0MB.`,
      }
    } catch {
      return fallback
    }
  })()
  return cached
}
