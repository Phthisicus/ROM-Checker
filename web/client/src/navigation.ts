import { useSyncExternalStore } from 'react'
import type { Tab } from './workspace'

const paths: Record<Tab, string> = {
  Library: 'library', Storage: 'add-games', Jobs: 'activity', Settings: 'settings',
  Integrations: 'settings/connections', Overview: 'tools/server', ExpertLibrary: 'tools/results',
  Changes: 'tools/moves', Recovery: 'tools/recovery',
}
let navigationGuard: (() => boolean) | undefined

export function guardNavigation(guard: () => boolean) {
  navigationGuard = guard
  const originalURL = location.href
  const originalState: unknown = history.state
  let handledURL: string | undefined
  const checkPop = (event: PopStateEvent) => {
    handledURL = location.href
    if (guard()) return
    history.replaceState(originalState, '', originalURL)
    event.stopImmediatePropagation()
  }
  const checkHash = (event: HashChangeEvent) => {
    if (event.newURL === handledURL || event.newURL && event.newURL !== location.href) return
    if (!event.oldURL || guard()) return
    history.replaceState(originalState, '', event.oldURL)
    event.stopImmediatePropagation()
  }
  window.addEventListener('popstate', checkPop, true)
  window.addEventListener('hashchange', checkHash, true)
  return () => {
    if (navigationGuard === guard) navigationGuard = undefined
    window.removeEventListener('popstate', checkPop, true)
    window.removeEventListener('hashchange', checkHash, true)
  }
}
const subscribe = (notify: () => void) => {
  window.addEventListener('hashchange', notify)
  return () => window.removeEventListener('hashchange', notify)
}
export function readRoute() {
  const [path, search = ''] = location.hash.replace(/^#\/?/, '').split('?')
  const integration = path.startsWith('settings/connections/') ? path.slice('settings/connections/'.length) : undefined
  const tab = integration !== undefined ? 'Integrations'
    : (Object.keys(paths) as Tab[]).find(key => paths[key] === path) ?? 'Library'
  return { tab, integration, params: new URLSearchParams(search) }
}
function write(hash: string, replace: boolean, state: unknown = null) {
  if (location.hash === hash) return
  if (navigationGuard && !navigationGuard()) return
  if (replace) history.replaceState(state, '', hash)
  else history.pushState(state, '', hash)
  window.dispatchEvent(new HashChangeEvent('hashchange'))
}
export function openIntegration(id: string) {
  write(`#/settings/connections/${encodeURIComponent(id)}`, false)
}
export function navigate(tab: Tab) {
  const route = readRoute()
  if (route.tab === 'Library') sessionStorage.setItem('romchecker-library-route', location.hash || '#/library')
  const saved = tab === 'Library' ? sessionStorage.getItem('romchecker-library-route') : null
  write(saved?.startsWith('#/library') ? saved : `#/${paths[tab]}`, false)
}
export function libraryRoute(values: Record<string, string>, replace = false) {
  const params = readRoute().params
  for (const [key, value] of Object.entries(values)) {
    if (value) params.set(key, value)
    else params.delete(key)
  }
  write(`#/library${params.size ? '?' + params.toString() : ''}`, replace,
    values.file && !replace ? { libraryParent: location.hash || '#/library' } : null)
}
export function closeLibraryFile() {
  if (typeof history.state?.libraryParent === 'string') history.back()
  else libraryRoute({ file: '' }, true)
}
export function useRoute() {
  useSyncExternalStore(subscribe, () => location.hash)
  return readRoute()
}
