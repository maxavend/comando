// Which download fits the visitor's computer. The page is built for Mac and
// switches to Windows in the browser, so without JavaScript nothing changes.
export type Platform = "mac" | "win-x64" | "win-arm64"

type UAData = {
  platform?: string
  getHighEntropyValues?: (hints: string[]) => Promise<{ architecture?: string }>
}

let detected: Promise<Platform | null> | undefined

/** The visitor's platform, or null when neither Mac nor Windows (a phone, Linux). */
export function detectPlatform(): Promise<Platform | null> {
  detected ??= (async () => {
    const data = (navigator as Navigator & { userAgentData?: UAData }).userAgentData
    const platform = data?.platform ?? navigator.platform ?? ""
    const ua = navigator.userAgent
    if (/^win/i.test(platform) || /Windows NT/.test(ua)) {
      // Only Chromium tells the processor; elsewhere x64, the common case.
      let arch = ""
      try {
        arch = (await data?.getHighEntropyValues?.(["architecture"]))?.architecture ?? ""
      } catch {
        // Not allowed here: x64 it is.
      }
      return arch === "arm" || /ARM64|aarch64/i.test(ua) ? "win-arm64" : "win-x64"
    }
    // An iPad asks for the desktop site as “MacIntel”, but has touch.
    if (/mac/i.test(platform) && navigator.maxTouchPoints < 2) return "mac"
    return null
  })()
  return detected
}

type Option = { href: string; button: string; note: string; name: string }

/**
 * On Windows, points every download at the visitor's processor: the buttons
 * built by `download.astro` and the links marked `data-download-href`.
 */
export async function applyDownloads() {
  const platform = await detectPlatform()
  if (!platform || platform === "mac") return

  for (const el of document.querySelectorAll<HTMLElement>("[data-download]")) {
    const options = JSON.parse(el.dataset.download ?? "{}") as Record<Platform, Option>
    const chosen = options[platform]
    const button = el.querySelector("a")
    const label = el.querySelector("[data-download-label]")
    const note = el.querySelector("[data-download-note]")
    const row = el.querySelector("[data-download-others]")
    if (!chosen || !button || !label || !note || !row) continue
    button.href = chosen.href
    label.textContent = chosen.button
    note.textContent = chosen.note
    const style = row.querySelector("a")?.className ?? ""
    // The other Windows first, it is the likelier mix-up.
    const [first, second] = (platform === "win-x64" ? ["win-arm64", "mac"] as const : ["win-x64", "mac"] as const)
      .map((p) => {
        const a = document.createElement("a")
        a.className = style
        a.href = options[p].href
        a.textContent = options[p].name
        return a
      })
    row.replaceChildren("¿Otro equipo? ", first, " o ", second, ".")
  }

  for (const el of document.querySelectorAll<HTMLElement>("[data-download-href]")) {
    const hrefs = JSON.parse(el.dataset.downloadHref ?? "{}") as Record<Platform, string>
    const a = el instanceof HTMLAnchorElement ? el : el.querySelector("a")
    if (a && hrefs[platform]) a.href = hrefs[platform]
  }
}
