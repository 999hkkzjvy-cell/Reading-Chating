import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const diagnosticSource = readFileSync(new URL('../src/authDiagnostics.js', import.meta.url), 'utf8');
const diagnostics = await import(`data:text/javascript;base64,${Buffer.from(diagnosticSource).toString('base64')}`);
const { authStep, createDiagnosticFetch, authDiagnosticReport } = diagnostics;
const user = { id: 'test-user' };
const session = { user };

function harness({ getUser, signIn, profile } = {}) {
  const state = new Map();
  const elements = new Map();
  const document = { getElementById(id) {
    if (!elements.has(id)) elements.set(id, { innerHTML: '', style: {} });
    return elements.get(id);
  } };
  const sb = {
    auth: {
      onAuthStateChange() {},
      getUser: getUser || (async () => ({ data: { user }, error: null })),
      signInWithPassword: signIn || (async () => ({ data: { user, session }, error: null })),
    },
    from: () => ({ select: () => ({ eq: () => ({
      single: profile || (async () => ({ data: { role: 'member' }, error: null })),
    }) }) }),
    rpc: async () => ({ data: 0 }),
  };
  const context = vm.createContext({
    sb, authStep, document, store: { get: key => state.get(key), set: (key, value) => state.set(key, value) },
    loadMemberSummary: async () => {}, console,
  });
  const source = readFileSync(new URL('../src/auth.js', import.meta.url), 'utf8')
    .replace(/import[\s\S]*?from '[^']+';\n/g, '')
    .replaceAll('export async function ', 'async function ')
    .replaceAll('export function ', 'function ');
  vm.runInContext(source, context);
  return { state, elements, run: code => vm.runInContext(code, context) };
}

test('successful password exchange does not require another getUser request', async () => {
  let identityRequests = 0;
  const h = harness({ getUser: async () => { identityRequests++; throw new TypeError('offline'); } });
  await h.run("signIn('test@example.invalid', 'test-password')");
  assert.equal(identityRequests, 0);
  assert.equal(h.state.get('authStatus'), 'ready');
  assert.equal(h.state.get('user'), user);
});

test('profile failure preserves verified identity without granting admin access', async () => {
  const h = harness({ profile: async () => ({ data: null, error: { message: 'untrusted detail', status: 503 } }) });
  await h.run("signIn('test@example.invalid', 'test-password')");
  assert.equal(h.state.get('authStatus'), 'profile-unavailable');
  assert.equal(h.state.get('user'), user);
  assert.equal(h.state.get('isAdmin'), false);
  assert.match(h.elements.get('nav-user').innerHTML, /个人中心/);
});

test('network failure during restore preserves existing state and offers uncertainty', async () => {
  const h = harness({ getUser: async () => ({ data: { user: null }, error: { name: 'AuthRetryableFetchError' } }) });
  h.state.set('user', user);
  await assert.rejects(h.run('initAuth()'));
  assert.equal(h.state.get('authStatus'), 'uncertain');
  assert.equal(h.state.get('user'), user);
});

test('an unverified visitor does not become authenticated on network failure', async () => {
  const h = harness({ getUser: async () => { throw new TypeError('failed fetch'); } });
  await assert.rejects(h.run('initAuth()'));
  assert.equal(h.state.get('user'), undefined);
  assert.match(h.elements.get('nav-user').innerHTML, /确认登录状态/);
});

test('missing session is anonymous, and manual retry can restore a verified user', async () => {
  let offline = true;
  const h = harness({ getUser: async () => offline
    ? { data: { user: null }, error: { name: 'AuthSessionMissingError' } }
    : { data: { user }, error: null } });
  await h.run('initAuth()');
  assert.equal(h.state.get('authStatus'), 'anonymous');
  offline = false;
  await h.run('initAuth()');
  assert.equal(h.state.get('authStatus'), 'ready');
});

test('late startup failure cannot overwrite a newer successful password login', async () => {
  let reject;
  const h = harness({ getUser: () => new Promise((_, no) => { reject = no; }) });
  const startup = h.run('initAuth()');
  await h.run("signIn('test@example.invalid', 'test-password')");
  reject(new TypeError('old request failed'));
  await startup;
  assert.equal(h.state.get('authStatus'), 'ready');
  assert.equal(h.state.get('user'), user);
});

test('concurrent restore attempts share one request', async () => {
  let resolve, calls = 0;
  const h = harness({ getUser: () => { calls++; return new Promise(yes => { resolve = yes; }); } });
  const first = h.run('initAuth()');
  const second = h.run('initAuth()');
  assert.equal(first, second);
  resolve({ data: { user }, error: null });
  await first;
  assert.equal(calls, 1);
});

test('diagnostic fetch preserves response, credentials, request signal and unrelated requests', async () => {
  const request = new Request('https://example.test/auth/v1/token?grant_type=password');
  const options = { method: 'POST', body: 'secret-body', headers: { Authorization: 'secret-token' },
    signal: new AbortController().signal };
  const response = new Response('private response', { status: 200 });
  let actual;
  const fetch = createDiagnosticFetch('https://example.test', async (...args) => { actual = args; return response; });
  assert.equal(await fetch(request, options), response);
  assert.equal(actual[0], request);
  assert.equal(actual[1], options);
  const before = authDiagnosticReport();
  await fetch('https://other.test/storage/v1/upload', options);
  assert.equal(authDiagnosticReport(), before);
  assert.equal(await response.text(), 'private response');
});

test('report retains refresh stage and errors, but never account, token, URL or raw error text', async () => {
  const error = new TypeError('private@example.invalid secret-token secret-password');
  const fetch = createDiagnosticFetch('https://example.test', async () => { throw error; });
  await assert.rejects(fetch('https://example.test/auth/v1/token?grant_type=refresh_token&secret=hidden'), e => e === error);
  const report = authDiagnosticReport();
  assert.match(report, /HTTP 会话刷新.*网络或程序异常/);
  assert.doesNotMatch(report, /private@example|secret-token|secret-password|hidden|https:/);
});

function feedbackHarness({ missingPanel = false } = {}) {
  const state = new Map(), subscriptions = {}, handlers = {}, timers = new Map(), navigations = [];
  let id = 0, requests = 0, resolve;
  const message = {}, retry = { addEventListener: (event, fn) => { handlers[event] = fn; } };
  const panel = { hidden: true, querySelector: key => key === '[data-auth-message]' ? message : retry };
  const report = {};
  const context = vm.createContext({
    document: {
      getElementById: () => missingPanel ? null : panel,
      querySelectorAll: () => [report],
      addEventListener: (event, fn) => { handlers[event] = fn; },
    },
    store: { get: key => state.get(key), on: (key, fn) => { subscriptions[key] = fn; } },
    router: { currentPath: () => '/login?redirect=%2Fmember', navigate: path => navigations.push(path) },
    initAuth: () => { requests++; return new Promise(yes => { resolve = yes; }); },
    authDiagnosticReport: () => 'safe diagnostic report', URLSearchParams,
    setTimeout: fn => { timers.set(++id, fn); return id; },
    clearTimeout: key => timers.delete(key),
  });
  const source = readFileSync(new URL('../src/authFeedback.js', import.meta.url), 'utf8')
    .replace(/import[\s\S]*?from '[^']+';\n/g, '')
    .replaceAll('export function ', 'function ');
  vm.runInContext(source, context);
  vm.runInContext('bindAuthFeedback()', context);
  return { panel, message, retry, handlers, timers, navigations, state, report,
    requests: () => requests, resolve: () => resolve(),
    status: value => { state.set('authStatus', value); subscriptions.authStatus(); } };
}

test('uncertain feedback retries without asking for password and avoids duplicate retry requests', async () => {
  const h = feedbackHarness();
  h.status('uncertain');
  assert.equal(h.panel.hidden, false);
  assert.match(h.message.textContent, /暂时无法确认/);
  const pending = h.handlers.click();
  await h.handlers.click();
  assert.equal(h.requests(), 1);
  assert.equal(h.retry.disabled, true);
  h.state.set('user', user);
  h.status('ready');
  h.resolve();
  await pending;
  assert.deepEqual(h.navigations, ['/member']);
  assert.equal(h.panel.hidden, true);
});

test('slow requests show a waiting notice without starting another request', () => {
  const h = feedbackHarness();
  h.status('signing-in');
  assert.equal(h.panel.hidden, true);
  [...h.timers.values()][0]();
  assert.equal(h.panel.hidden, false);
  assert.match(h.message.textContent, /响应较慢/);
  assert.equal(h.retry.hidden, true);
  assert.equal(h.requests(), 0);
  h.status('ready');
  assert.equal(h.panel.hidden, true);
  assert.equal(h.timers.size, 0);
});

test('missing feedback panel in an older HTML shell never blocks app initialization', () => {
  assert.doesNotThrow(() => feedbackHarness({ missingPanel: true }));
});
