import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuLinkItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

type Link = { href: string; label: string; current: boolean }

// The phone menu: the same four pages as the capsule, under a "Menú" pill.
export function MobileMenu({ links }: { links: Link[] }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button variant="ghost" size="pill" className="px-4" />}>
        Menú
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" sideOffset={10} className="w-72 max-w-[calc(100vw-2rem)] max-h-[calc(100dvh-6rem)] overflow-y-auto rounded-2xl p-2 shadow-nav">
        <DropdownMenuGroup>
          {links.map((link) => (
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
