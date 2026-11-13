import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { Button, EmptyState, IconButton, Notice, Select, Table, TextInput, Tooltip } from './components'
import { Dialog } from './Dialog'

describe('design system behavior', () => {
  it('keeps incidental buttons out of form submission and blocks duplicate pending actions', () => {
    const submit = vi.fn(event => event.preventDefault())
    const action = vi.fn()
    const { rerender } = render(<form onSubmit={submit}><Button onClick={action}>Check selected</Button></form>)
    fireEvent.click(screen.getByRole('button', { name: 'Check selected' }))
    expect(action).toHaveBeenCalledOnce()
    expect(submit).not.toHaveBeenCalled()
    rerender(<Button loading onClick={action}>Check selected</Button>)
    const button = screen.getByRole('button', { name: 'Check selected' })
    expect(button).toHaveAttribute('aria-busy', 'true')
    fireEvent.click(button)
    expect(action).toHaveBeenCalledOnce()
  })

  it('connects unique labels, hints and errors without dropping caller descriptions or input behavior', () => {
    const change = vi.fn()
    render(<><span id="external">Server path only.</span><TextInput label="Export directory" hint="Use a shared mount." error="Directory is required." aria-describedby="external" onChange={change} /><TextInput label="Import directory" /><Select label="Console" error="Select a console."><option value="">Choose</option><option>NES</option></Select></>)
    const input = screen.getByLabelText('Export directory')
    expect(input).toHaveAccessibleDescription('Server path only. Use a shared mount. Directory is required.')
    expect(input).toHaveAttribute('aria-invalid', 'true')
    expect(input.id).not.toBe(screen.getByLabelText('Import directory').id)
    fireEvent.change(input, { target: { value: '/exports' } })
    expect(change).toHaveBeenCalledOnce()
    expect(screen.getByRole('combobox', { name: 'Console' })).toHaveAccessibleDescription('Select a console.')
  })

  it('announces errors urgently and success politely with explicit dismissal', () => {
    const dismiss = vi.fn()
    render(<><Notice tone="danger" onDismiss={dismiss}>RomM is unavailable. Retry the connection.</Notice><Notice tone="success">Settings saved.</Notice></>)
    expect(screen.getByRole('alert')).toHaveTextContent('RomM is unavailable')
    expect(screen.getByRole('status')).toHaveTextContent('Settings saved.')
    fireEvent.click(screen.getByRole('button', { name: 'Dismiss notification' }))
    expect(dismiss).toHaveBeenCalledOnce()
  })

  it('preserves tooltip trigger behavior, associations, and Escape dismissal', () => {
    const click = vi.fn()
    render(<><span id="prior">Existing description.</span><Tooltip content="Checks do not move originals."><button aria-describedby="prior" onClick={click}>Check ROM</button></Tooltip><IconButton label="Open details"><span aria-hidden="true">+</span></IconButton></>)
    const trigger = screen.getByRole('button', { name: 'Check ROM' })
    fireEvent.focus(trigger)
    expect(trigger).toHaveAccessibleDescription('Existing description. Checks do not move originals.')
    fireEvent.click(trigger)
    expect(click).toHaveBeenCalledOnce()
    fireEvent.keyDown(trigger, { key: 'Escape' })
    expect(screen.queryByRole('tooltip')).not.toBeInTheDocument()
    expect(trigger).toHaveAttribute('aria-describedby', 'prior')
    fireEvent.mouseEnter(trigger.parentElement!)
    expect(screen.getByRole('tooltip')).toBeInTheDocument()
    fireEvent.mouseLeave(trigger.parentElement!)
    expect(screen.queryByRole('tooltip')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Open details' })).toBeInTheDocument()
  })

  it('protects pending dialogs from cancellation and restores a connected opener', () => {
    const close = vi.fn()
    const opener = document.createElement('button')
    document.body.append(opener)
    opener.focus()
    const { rerender, unmount } = render(<Dialog title="Publish eligible ROMs" description="Only approved working copies." onClose={close} closeDisabled><p>Publishing...</p></Dialog>)
    const dialog = screen.getByRole('dialog', { name: 'Publish eligible ROMs' })
    expect(dialog).toHaveAccessibleDescription('Only approved working copies.')
    expect(screen.getByRole('button', { name: 'Close dialog' })).toBeDisabled()
    fireEvent(dialog, new Event('cancel', { cancelable: true }))
    expect(close).not.toHaveBeenCalled()
    rerender(<Dialog title="Publish eligible ROMs" onClose={close} variant="drawer"><p>Ready.</p></Dialog>)
    fireEvent(dialog, new Event('cancel', { cancelable: true }))
    expect(close).toHaveBeenCalledOnce()
    expect(dialog).toHaveClass('ds-drawer')
    unmount()
    expect(opener).toHaveFocus()
    opener.remove()
  })

  it('provides named, keyboard-scrollable tables and actionable empty states', () => {
    const add = vi.fn()
    render(<><Table caption="ROM integrity"><thead><tr><th scope="col">File</th><th scope="col">Integrity</th></tr></thead><tbody><tr><td>Game.nes</td><td>Unchecked</td></tr></tbody></Table><EmptyState title="No ROMs yet" action={<Button onClick={add}>Add games</Button>}>Import files to begin checking.</EmptyState></>)
    expect(screen.getByRole('table', { name: 'ROM integrity' })).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'ROM integrity' })).toHaveAttribute('tabindex', '0')
    fireEvent.click(screen.getByRole('button', { name: 'Add games' }))
    expect(add).toHaveBeenCalledOnce()
  })
})
