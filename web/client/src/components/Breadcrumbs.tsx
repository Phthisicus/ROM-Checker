import { ChevronRight } from 'lucide-react'
import { Fragment } from 'react'
import { navigate } from '../navigation'
import type { Tab } from '../workspace'

const titles: Record<Tab, string> = {
  Library: 'Library', Storage: 'Add games', Jobs: 'Activity', Settings: 'Settings',
  Integrations: 'Connections', Overview: 'Server tools', ExpertLibrary: 'Detailed results',
  Changes: 'Move previews', Recovery: 'Recovery',
}

export default function Breadcrumbs({ tab, integration }: { tab: Tab; integration?: string }) {
  const items: { title: string; tab?: Tab; href?: string }[] = [
    { title: 'Your collection', tab: 'Library', href: '#/library' },
  ]
  if (tab === 'Integrations') items.push({ title: 'Settings', tab: 'Settings', href: '#/settings' })
  items.push({ title: titles[tab], tab, href: tab === 'Integrations' ? '#/settings/connections' : undefined })
  if (tab === 'Integrations' && integration !== undefined)
    items.push({ title: integration === 'romm' ? 'RomM' : 'Unknown integration' })
  return <nav className="breadcrumb" aria-label="Breadcrumb">
    {items.map((item, index) => <Fragment key={`${index}-${item.title}`}>
      {index > 0 && <ChevronRight size={14} aria-hidden="true" />}
      {index === items.length - 1 ? <strong aria-current="page">{item.title}</strong>
        : <a href={item.href} onClick={event => {
          if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || !item.tab) return
          event.preventDefault()
          navigate(item.tab)
        }}>{item.title}</a>}
    </Fragment>)}
  </nav>
}
