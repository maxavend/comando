import { useRef } from "react"
import { Button } from "@/components/ui/button"

const root = () => document.documentElement
const ms = (name: string) => parseFloat(getComputedStyle(root()).getPropertyValue(name)) || 0

type MorphEl = HTMLElement & { _morphTimer?: number }

// Text morph from transitions-dev: the letters both labels share stay put;
// only the part that differs cross-blurs, while its width eases.
function morphText(el: MorphEl, next: string) {
  const prev = el.dataset.text ?? el.textContent ?? ""
  if (prev === next) return
  el.dataset.text = next
  clearTimeout(el._morphTimer)

  let a = 0
  while (a < prev.length && a < next.length && prev[a] === next[a]) a++
  let b = 0
  while (b < prev.length - a && b < next.length - a && prev[prev.length - 1 - b] === next[next.length - 1 - b]) b++

  const swap = document.createElement("span")
  swap.className = "t-morph-swap"
  const out = document.createElement("span")
  out.className = "t-morph-old"
  out.setAttribute("aria-hidden", "true")
  out.textContent = prev.slice(a, prev.length - b)
  const inn = document.createElement("span")
  inn.className = "t-morph-new"
  inn.textContent = next.slice(a, next.length - b)
  swap.append(out, inn)

  el.textContent = ""
  el.append(next.slice(0, a), swap, next.slice(next.length - b))

  swap.style.width = out.getBoundingClientRect().width + "px"
  void swap.offsetWidth
  swap.classList.add("is-morphing")
  swap.style.width = inn.getBoundingClientRect().width + "px"

  el._morphTimer = window.setTimeout(() => {
    el.textContent = next
  }, Math.max(ms("--text-morph-dur"), ms("--text-morph-resize-dur")) + 40)
}

// A copy button for a command block. React never re-renders the label, so
// morphText can own its contents.
export function CopyCode({ code }: { code: string }) {
  const label = useRef<HTMLSpanElement>(null)
  const reset = useRef<number>(undefined)

  async function copy() {
    const el = label.current
    if (!el) return
    clearTimeout(reset.current)
    try {
      await navigator.clipboard.writeText(code)
      morphText(el, "Copiado")
    } catch {
      morphText(el, "No se pudo copiar")
    }
    reset.current = window.setTimeout(() => morphText(el, "Copiar"), 1800)
  }

  return (
    <Button type="button" variant="outline" size="sm" onClick={copy} className="absolute top-3 right-3 h-8 px-3 text-sm">
      <span ref={label} className="t-morph" aria-live="polite">
        Copiar
      </span>
    </Button>
  )
}
