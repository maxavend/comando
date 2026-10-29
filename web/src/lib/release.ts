import { releasesUrl, repo } from "./site"

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

export type WindowsRelease = { x64: string; arm64: string; version: string | null }

let cachedWindows: Promise<WindowsRelease> | undefined

// The Windows version ships as its own prerelease (tag `windows-vX.Y.Z`), so
// `releases/latest` never returns it: look through the recent releases for
// the newest one and its installer for each processor (the portable .zip in
// versions before the installer).
export function windowsRelease(): Promise<WindowsRelease> {
  cachedWindows ??= (async () => {
    const fallback = { x64: `${repo}/releases`, arm64: `${repo}/releases`, version: null }
    try {
      const headers: Record<string, string> = { Accept: "application/vnd.github+json" }
      if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`
      const res = await fetch("https://api.github.com/repos/maxavend/comando/releases?per_page=30", { headers })
      if (!res.ok) return fallback
      const releases: { tag_name: string; draft: boolean; assets?: { name: string; size: number; browser_download_url: string }[] }[] = await res.json()
      const release = releases.find((r) => !r.draft && r.tag_name.startsWith("windows-v"))
      const download = (arch: string) =>
        release?.assets?.find((a) => a.name.endsWith(`-${arch}-setup.exe`)) ??
        release?.assets?.find((a) => a.name.endsWith(`-${arch}-portable.zip`))
      const x64 = download("x64")
      const arm64 = download("ARM64")
      if (!release || !x64 || !arm64) return fallback
      return {
        x64: x64.browser_download_url,
        arm64: arm64.browser_download_url,
        version: release.tag_name.replace(/^windows-v/, ""),
      }
    } catch {
      return fallback
    }
  })()
  return cachedWindows
}
