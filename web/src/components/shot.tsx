import { Dialog, DialogContent, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { cn } from "@/lib/utils"
import { useEffect, useRef, useState } from "react"

type Props = {
  light: string
  dark?: string
  alt: string
  width?: number
  height?: number
  srcSet?: { light: string; dark?: string }
  sizes?: string
  priority?: boolean
  onBand?: boolean
  className?: string
}

function Capture({ light, dark, alt, width = 1600, height = 1048, srcSet, sizes, priority, className }: Props) {
  const imageRef = useRef<HTMLImageElement>(null)
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    const image = imageRef.current
    if (image?.complete && image.naturalWidth > 0) setLoaded(true)
  }, [])

  return (
    <div
      className={cn("t-skel shot-loading", loaded && "is-revealed")}
      data-state={loaded ? "loaded" : "loading"}
      style={{ aspectRatio: `${width} / ${height}` }}
    >
      <div className="t-skel-skeleton is-pulsing" aria-hidden="true">
        <span />
      </div>
      <picture className="t-skel-content">
        {dark && <source media="(prefers-color-scheme: dark)" srcSet={srcSet?.dark ?? dark} sizes={sizes} />}
        <img
          ref={imageRef}
          src={light}
          srcSet={srcSet?.light}
          sizes={sizes}
          width={width}
          height={height}
          alt={alt}
          className={className}
          onLoad={() => setLoaded(true)}
          onError={() => setLoaded(true)}
          {...(priority ? { fetchPriority: "high" as const } : { loading: "lazy" as const, decoding: "async" as const })}
        />
      </picture>
    </div>
  )
}

// A capture of the app. A click opens it large; on a phone it can be panned to read it.
export function Shot(props: Props) {
  const { alt, onBand, className } = props
  return (
    <Dialog>
      <DialogTrigger
        render={
          <button
            type="button"
            className={cn(
              "block w-full cursor-zoom-in rounded-xl focus-visible:outline-2 focus-visible:outline-offset-4",
              onBand ? "focus-visible:outline-band-foreground" : "focus-visible:outline-ring",
              className
            )}
          />
        }
      >
        <span className="sr-only">Ampliar captura. </span>
        <Capture {...props} className={onBand ? "[filter:var(--shadow-shot-band)]" : "shot-shadow"} />
      </DialogTrigger>
      <DialogContent className="top-0 left-0 h-dvh w-screen max-w-none translate-0 rounded-none bg-band/95 p-0 text-band-foreground ring-0 sm:max-w-none [&_[data-slot=dialog-close]]:size-11 [&_[data-slot=dialog-close]]:top-[max(0.5rem,env(safe-area-inset-top))] [&_[data-slot=dialog-close]]:right-[max(0.5rem,env(safe-area-inset-right))]">
        <DialogTitle className="sr-only">{alt}</DialogTitle>
        <div
          ref={(view) => {
            if (view) requestAnimationFrame(() => view.scrollTo({ left: (view.scrollWidth - view.clientWidth) / 2 }))
          }}
          className="grid h-dvh place-items-center overflow-auto overscroll-contain px-16 pt-24 pb-16 max-sm:place-items-center-safe max-sm:px-4 max-sm:justify-items-start">
          <Capture {...props} priority className="w-[min(100%,1600px)] [filter:var(--shadow-shot-band)] max-sm:w-[1100px] max-sm:max-w-none" />
        </div>
      </DialogContent>
    </Dialog>
  )
}
