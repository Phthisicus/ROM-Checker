import { afterEach, describe, expect, it, vi } from 'vitest'
import { guardNavigation, navigate, openIntegration, readRoute } from './navigation'

afterEach(() => { history.replaceState(null, '', '/') })

describe('integration navigation', () => {
  it('distinguishes the overview, detail pages, and unknown integration IDs', () => {
    navigate('Integrations')
    expect(readRoute()).toMatchObject({ tab: 'Integrations', integration: undefined })
    openIntegration('romm')
    expect(readRoute()).toMatchObject({ tab: 'Integrations', integration: 'romm' })
    openIntegration('missing')
    expect(readRoute()).toMatchObject({ tab: 'Integrations', integration: 'missing' })
  })

  it('blocks programmatic navigation until leaving is confirmed and removes the guard on cleanup', () => {
    openIntegration('romm')
    const guard = vi.fn().mockReturnValue(false)
    const cleanup = guardNavigation(guard)
    try {
      navigate('Integrations')
      expect(readRoute().integration).toBe('romm')
      guard.mockReturnValue(true)
      navigate('Integrations')
      expect(readRoute().integration).toBeUndefined()
    } finally { cleanup() }
    openIntegration('romm')
    expect(guard).toHaveBeenCalledTimes(2)
  })

  it('restores a rejected native hash navigation before route subscribers are notified', () => {
    openIntegration('romm')
    const oldURL = location.href
    const cleanup = guardNavigation(() => false)
    const notified = vi.fn()
    window.addEventListener('hashchange', notified)
    try {
      history.replaceState(null, '', '#/settings/connections')
      window.dispatchEvent(new HashChangeEvent('hashchange', { oldURL, newURL: location.href }))
      expect(readRoute().integration).toBe('romm')
      expect(notified).not.toHaveBeenCalled()
    } finally { cleanup(); window.removeEventListener('hashchange', notified) }
  })
})
