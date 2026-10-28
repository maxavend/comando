import type { ComponentProps } from "react"
import { DownloadIcon } from "lucide-react"
import { Button } from "@/components/ui/button"

type Props = Omit<ComponentProps<typeof Button>, "render" | "nativeButton"> & {
  href: string
  download?: boolean
}

// shadcn's Button rendered as a link. Astro can't pass a JSX element as a
// React prop, so pages use this instead of Button's `render`.
export function LinkButton({ href, download, children, ...props }: Props) {
  return (
    <Button render={<a href={href} />} nativeButton={false} {...props}>
      {download && <DownloadIcon data-icon="inline-start" />}
      {children}
    </Button>
  )
}
