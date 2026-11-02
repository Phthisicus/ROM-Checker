import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import Breadcrumbs from './Breadcrumbs'
import { readRoute } from '../navigation'
import type { Tab } from '../workspace'

describe('main breadcrumb', () => {
  it.each<[Tab, string]>([
    ['Library', 'Library'], ['Storage', 'Add games'], ['Jobs', 'Activity'],
    ['Settings', 'Settings'], ['Integrations', 'Connections'], ['Overview', 'Server tools'],
    ['ExpertLibrary', 'Detailed results'], ['Changes', 'Move previews'], ['Recovery', 'Recovery'],
  ])('includes %s in the main navigation trail', (tab, title) => {
    render(<Breadcrumbs tab={tab} />)
    const trail = screen.getByRole('navigation', { name: 'Breadcrumb' })
    expect(trail.querySelector('[aria-current="page"]')).toHaveTextContent(title)
    expect(within(trail).getByRole('link', { name: 'Your collection' })).toHaveAttribute('href', '#/library')
  })

  it('includes integration ancestors and navigates to them', () => {
    render(<Breadcrumbs tab="Integrations" integration="romm" />)
    const trail = screen.getByRole('navigation', { name: 'Breadcrumb' })
    expect(trail.querySelector('[aria-current="page"]')).toHaveTextContent('RomM')
    expect(within(trail).getByRole('link', { name: 'Settings' })).toHaveAttribute('href', '#/settings')
    fireEvent.click(within(trail).getByRole('link', { name: 'Connections' }))
    expect(readRoute()).toMatchObject({ tab: 'Integrations', integration: undefined })
    history.replaceState(null, '', '/')
  })
})
