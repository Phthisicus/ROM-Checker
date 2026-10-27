import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach, beforeEach, vi } from 'vitest';

beforeEach(() => {
  history.replaceState(null, '', location.pathname)
  localStorage.clear()
  sessionStorage.clear()
})

afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.unstubAllGlobals() })
HTMLDialogElement.prototype.showModal = function () { this.setAttribute('open', '') }
HTMLDialogElement.prototype.close = function () { this.removeAttribute('open') }
