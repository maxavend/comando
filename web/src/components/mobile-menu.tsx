import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuLinkItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { detectPlatform, type Platform } from "@/lib/platform"

type Link = { href: string; label: string; current: boolean }

// The phone menu: the same four pages as the capsule, under a "Menú" pill,
// and the download for the visitor's computer.
export function MobileMenu({ links, downloads }: { links: Link[]; downloads: Record<Platform, string> }) {
  const [platform, setPlatform] = useState<Platform>("mac")
  useEffect(() => {
    detectPlatform().then((p) => p && setPlatform(p))
  }, [])
  const download = { href: downloads[platform], label: platform === "mac" ? "Descargar para Mac" : "Descargar para Windows", current: false }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button variant="ghost" size="pill" className="px-4" />}>
        Menú
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" sideOffset={10} className="w-72 max-w-[calc(100vw-2rem)] max-h-[calc(100dvh-6rem)] overflow-y-auto rounded-2xl p-2 shadow-nav">
        <DropdownMenuGroup>
          {[...links, download].map((link) => (
            <DropdownMenuLinkItem
              key={link.href}
              href={link.href}
              aria-current={link.current ? "page" : undefined}
              className="min-h-12 rounded-lg px-4 text-lg aria-[current=page]:bg-accent"
            >
              {link.label}
            </DropdownMenuLinkItem>
          ))}
        </DropdownMenuGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
