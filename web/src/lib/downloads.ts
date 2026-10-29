import type { Platform } from "./platform"
import { latestRelease, windowsRelease } from "./release"

export type DownloadOption = { href: string; button: string; note: string; name: string }

// What each download button offers, read from GitHub once per build. The
// browser picks one with `applyDownloads()`.
export async function downloadOptions(macNote = ""): Promise<Record<Platform, DownloadOption>> {
  const [mac, win] = await Promise.all([latestRelease(), windowsRelease()])
  const version = win.version ? `Versión de prueba ${win.version}` : "Versión de prueba"
  return {
    mac: { href: mac.href, button: "Descargar para Mac", note: macNote, name: "Mac" },
    "win-x64": {
      href: win.x64,
      button: "Descargar para Windows",
      note: `${version}. Windows 10 y 11, PC x64.`,
      name: "Windows x64",
    },
    "win-arm64": {
      href: win.arm64,
      button: "Descargar para Windows",
      note: `${version}. Windows 10 y 11, PC ARM64.`,
      name: "Windows ARM64",
    },
  }
}

/** Only the links, for the header and footer. */
export async function downloadHrefs(): Promise<Record<Platform, string>> {
  const options = await downloadOptions()
  return { mac: options.mac.href, "win-x64": options["win-x64"].href, "win-arm64": options["win-arm64"].href }
}
