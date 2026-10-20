import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = name => readFileSync(new URL(`../src/${name}.js`, import.meta.url), 'utf8')
  .replace(/import[\s\S]*?from '[^']+';\n/g, '')
  .replaceAll('export function ', 'function ')
  .replaceAll('export async function ', 'async function ');

function authHarness(href) {
  const data = new Map();
  let authEvent;
  let updates = 0;
  const window = {
    location: { href },
    dispatchEvent() {},
    history: { replaceState(_state, _title, next) { window.location.href = next; } },
  };
  const sessionStorage = {
    getItem: key => data.get(key) ?? null,
    setItem: (key, value) => data.set(key, value),
    removeItem: key => data.delete(key),
  };
  const sb = { auth: {
    onAuthStateChange: callback => { authEvent = callback; },
    getSession: async () => ({ data: { session: { user: { id: 'recovery-user' } } }, error: null }),
    updateUser: async () => { updates++; return { error: null }; },
    signOut: async () => ({ error: null }),
  } };
  const context = vm.createContext({ sb, window, sessionStorage, URL, URLSearchParams,
    store: { set() {}, get: () => null },
    document: { getElementById: () => ({ innerHTML: '' }) },
    toast() {},
    setTimeout: callback => callback(),
    CustomEvent: class { constructor(type) { this.type = type; } } });
  vm.runInContext(source('auth'), context);
  return { data, window, emit: (event, session) => authEvent(event, session),
    run: code => vm.runInContext(code, context), updates: () => updates };
}

test('invalid recovery redirect cannot show a usable reset session', async () => {
  const h = authHarness('https://example.test/?auth_action=reset-password#error=access_denied&error_code=otp_expired');
  h.data.set('password_recovery_pending', 'recovery-user');
  assert.equal(h.run('getAuthRedirectRoute()'), '/reset-password');
  assert.equal(h.data.has('password_recovery_pending'), false);
  h.run("replaceAuthRedirectRoute('/reset-password')");
  assert.equal(await h.run('hasPasswordRecoverySession()'), false);
  await assert.rejects(h.run("completePasswordReset('new-test-password')"), { code: 'recovery_session_missing' });
  assert.equal(h.updates(), 0);
});

test('valid recovery event retains authorization while cleaning the redirect URL', async () => {
  const h = authHarness('https://example.test/?auth_action=reset-password#access_token=example&type=recovery');
  h.emit('PASSWORD_RECOVERY', { user: { id: 'recovery-user' } });
  h.run("replaceAuthRedirectRoute('/reset-password')");
  assert.equal(h.data.get('password_recovery_pending'), 'recovery-user');
  assert.equal(await h.run('hasPasswordRecoverySession()'), true);
  assert.equal(h.window.location.href, 'https://example.test/#/reset-password');
  h.data.set('password_recovery_pending', 'another-user');
  assert.equal(await h.run('hasPasswordRecoverySession()'), false);
});

test('valid recovery session can update the password and clears its pending state', async () => {
  const h = authHarness('https://example.test/?auth_action=reset-password#type=recovery');
  h.emit('PASSWORD_RECOVERY', { user: { id: 'recovery-user' } });
  await h.run("completePasswordReset('new-test-password')");
  assert.equal(h.updates(), 1);
  assert.equal(h.data.has('password_recovery_pending'), false);
});

test('reset route offers a new email when no recovery session exists', async () => {
  const routes = new Map();
  const context = vm.createContext({ route: (path, handler) => routes.set(path, handler),
    hasPasswordRecoverySession: async () => false });
  vm.runInContext(source('authPages'), context);
  vm.runInContext('registerAuthRoutes()', context);
  const html = await routes.get('/reset-password')();
  assert.match(html, /重置链接已失效/);
  assert.match(html, /重新发送重置邮件/);
  assert.doesNotMatch(html, /id="reset-form"/);
});

test('reset route shows the password form when the recovery session is valid', async () => {
  const routes = new Map();
  const context = vm.createContext({ route: (path, handler) => routes.set(path, handler),
    hasPasswordRecoverySession: async () => true });
  vm.runInContext(source('authPages'), context);
  vm.runInContext('registerAuthRoutes()', context);
  const html = await routes.get('/reset-password')();
  assert.match(html, /id="reset-form"/);
  assert.doesNotMatch(html, /重置链接已失效/);
});
