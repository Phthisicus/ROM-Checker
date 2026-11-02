import { fireEvent, render, screen, within } from '@testing-library/react'
import { useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import RommChecklist from './RommChecklist'

describe('RomM checkbox selections', () => {
  it('searches and selects shown options without dropping hidden or unavailable selections', () => {
    function Example() {
      const [selected, change] = useState(['missing'])
      return <RommChecklist title="Consoles" disabled={false} empty="No consoles"
        choices={[{ id: 'nes', name: 'NES' }, { id: 'snes', name: 'SNES' }, { id: 'gb', name: 'Game Boy' }]}
        selected={selected} change={change} />
    }
    render(<Example />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Game Boy' }))
    fireEvent.change(screen.getByRole('searchbox', { name: 'Search consoles' }), { target: { value: 'nes' } })
    fireEvent.click(screen.getByRole('button', { name: 'Select all shown' }))
    expect(screen.getByText('4 selected')).toBeInTheDocument()
    expect(screen.getByRole('checkbox', { name: 'NES' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'SNES' })).toBeChecked()
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: '' } })
    expect(screen.getByRole('checkbox', { name: 'Game Boy' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'missing (not currently available)' })).toBeChecked()
    fireEvent.click(screen.getByRole('button', { name: 'Clear selection' }))
    expect(screen.getByText('0 selected')).toBeInTheDocument()
  })

  it('shows empty search results without changing selections and respects disabled state', () => {
    const change = vi.fn()
    const { rerender } = render(<RommChecklist title="Imports" disabled={false} empty="No imports"
      choices={[{ id: 'a', name: 'Collection' }]} selected={['a']} change={change} />)
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'absent' } })
    expect(screen.getByText('No matching options. Your selections are unchanged.')).toBeInTheDocument()
    expect(change).not.toHaveBeenCalled()
    rerender(<RommChecklist title="Imports" disabled empty="No imports"
      choices={[{ id: 'a', name: 'Collection' }]} selected={['a']} change={change} />)
    expect(screen.getByRole('searchbox')).toBeDisabled()
    for (const button of within(screen.getByRole('group')).getAllByRole('button')) expect(button).toBeDisabled()
  })
})
