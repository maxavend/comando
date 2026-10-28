import { useEffect, useRef, useState } from "react"
import { Shot } from "@/components/shot"

export type Moment = {
  id: string
  label: string
  title: string
  body: string
  light: string
  dark: string
  alt: string
}

type Props = { heading: string; lead: string; items: Moment[] }

// Native scrolling drives both the reading rail and the capture selection.
export function FeatureStage({ heading, lead, items }: Props) {
  const root = useRef<HTMLElement>(null)
  const pane = useRef<HTMLDivElement>(null)
  const list = useRef<HTMLDivElement>(null)
  const rail = useRef<HTMLOListElement>(null)
  const [active, setActive] = useState(0)

  useEffect(() => {
    const column = list.current
    const sidebar = pane.current
    if (!column || !sidebar) return
    const figures = [...column.querySelectorAll<HTMLElement>("[data-figure]")]
    if (!figures.length) return
    const labels = [...(rail.current?.querySelectorAll<HTMLElement>(".moments-rail__label") ?? [])]
    let frame = 0
    let centres: number[] = []
    let columnTop = 0
    let nav = 96
    const desktop = matchMedia("(min-width: 60rem)")

    const update = () => {
      frame = 0
      if (!desktop.matches) return
      const centre = scrollY + (nav + innerHeight) / 2
      let step = 0
      for (let i = 0; i < centres.length - 1; i++) {
        if (centre >= centres[i]) {
          step = i + Math.min(1, (centre - centres[i]) / (centres[i + 1] - centres[i]))
        }
      }
      rail.current?.style.setProperty("--progress", String(step / Math.max(1, centres.length - 1)))
      // Interpolate between neighbouring captures, reaching full size exactly
      // at their centre. Smoothstep keeps growth gentle at both ends.
      labels.forEach((label, i) => {
        const proximity = Math.max(0, 1 - Math.abs(step - i))
        const emphasis = proximity * proximity * (3 - 2 * proximity)
        label.style.setProperty("--label-scale", String(1 + emphasis * 0.22))
      })
      setActive(Math.round(step))
      const px = (y: number) => `${y + scrollY - columnTop}px`
      column.style.setProperty("--fade-0", px(nav))
      column.style.setProperty("--fade-1", px(nav + 48))
      column.style.setProperty("--fade-2", px(innerHeight - 48))
      column.style.setProperty("--fade-3", px(innerHeight))
    }
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update)
    }
    const measure = () => {
      nav = parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop) || 96
      centres = figures.map((figure) => {
        const rect = (figure.querySelector("button") ?? figure).getBoundingClientRect()
        return scrollY + rect.top + rect.height / 2
      })
      columnTop = scrollY + column.getBoundingClientRect().top
      const height = sidebar.offsetHeight
      root.current?.style.setProperty("--pane-h", `${height}px`)
      root.current?.style.setProperty("--pane-start", `${Math.max(0, centres[0] - columnTop - height / 2)}px`)
      root.current?.style.setProperty("--pane-end", `${Math.max(0, columnTop + column.offsetHeight - centres[centres.length - 1] - height / 2)}px`)
      schedule()
    }
    const observer = new ResizeObserver(measure)
    observer.observe(column)
    observer.observe(sidebar)
    figures.forEach((figure) => observer.observe(figure))
    measure()
    addEventListener("scroll", schedule, { passive: true })
    addEventListener("resize", measure)
    desktop.addEventListener("change", measure)
    return () => {
      observer.disconnect()
      removeEventListener("scroll", schedule)
      removeEventListener("resize", measure)
      desktop.removeEventListener("change", measure)
      cancelAnimationFrame(frame)
    }
  }, [items])

  const go = (i: number) => (e: React.MouseEvent<HTMLAnchorElement>) => {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return
    const figure = list.current?.querySelectorAll<HTMLElement>("[data-figure]")[i]
    if (!figure) return
    e.preventDefault()
    const nav = parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop) || 96
    const rect = figure.getBoundingClientRect()
    const image = (figure.querySelector("button") ?? figure).getBoundingClientRect()
    // Centre the image while keeping its caption below the navigation.
    const inset = Math.max(nav + 16, (nav + innerHeight - image.height) / 2 - (image.top - rect.top))
    scrollTo({
      top: scrollY + rect.top - inset,
      behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth",
    })
  }

  return (
    <section ref={root} aria-labelledby="momentos" className="pt-36 pb-12 max-lg:py-24 max-sm:py-18">
      <div className="page grid items-start gap-16 max-sm:gap-8 lg:grid-cols-[minmax(0,4fr)_minmax(0,8fr)]">
        <div className="self-stretch lg:pt-(--pane-start) lg:pb-(--pane-end)">
        <div ref={pane} className="self-start lg:sticky lg:top-[max(7rem,calc((6rem+100dvh-var(--pane-h,28rem))/2))]">
          <h2 id="momentos" className="display max-w-[30ch] text-section">
            {heading}
          </h2>
          <p className="mt-4 text-lead text-ink-2">{lead}</p>
          <ol
            ref={rail}
            className="moments-rail relative mt-10 max-lg:hidden"
            style={{ "--steps": items.length - 1 } as React.CSSProperties}
          >
            {/* The rail runs from the first word's middle to the last one's. */}
            <span aria-hidden="true" className="moments-rail__track" />
            <span aria-hidden="true" className="moments-rail__fill" />
            <span aria-hidden="true" className="moments-rail__knob" />
            {items.map(({ id, label }, i) => (
              <li key={id} className="relative">
                <a
                  href={`#${id}`}
                  onClick={go(i)}
                  aria-current={active === i ? "step" : undefined}
                  data-passed={i < active ? "" : undefined}
                  className="moments-rail__item group flex h-14 items-center pl-8 focus-visible:-outline-offset-2"
                >
                  <span className="moments-rail__label">{label}</span>
                </a>
              </li>
            ))}
          </ol>
        </div>
        </div>

        <div
          ref={list}
          className="window-fade grid w-full gap-16 lg:max-w-[calc((80svh-12rem)*1.53)] lg:gap-28 lg:justify-self-end"
        >
          {items.map((m) => (
            <figure
              key={m.id}
              id={m.id}
              data-figure
              className="m-0 scroll-mt-[calc(var(--nav-height)+2.5rem)]"
            >
              <figcaption className="mb-6 grid max-w-[56ch] gap-2 text-ink-2">
                <h3 className="display text-title text-foreground" dangerouslySetInnerHTML={{ __html: m.title }} />
                <p dangerouslySetInnerHTML={{ __html: m.body }} />
              </figcaption>
              <Shot light={m.light} dark={m.dark} alt={m.alt} />
            </figure>
          ))}
        </div>
      </div>
    </section>
  )
}
