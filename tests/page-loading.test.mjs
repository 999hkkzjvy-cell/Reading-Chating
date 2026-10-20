import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = name => readFileSync(new URL(`../src/${name}.js`, import.meta.url), 'utf8')
  .replace(/^import[\s\S]*?;\s*$/gm, '')
  .replace(/\bexport /g, '');
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const flush = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };

function harness(path = '/') {
  const view = { innerHTML: '' };
  const state = {};
  const timers = new Map();
  const events = {};
  let nextTimer = 0;
  let reloads = 0;
  const context = vm.createContext({
    console: { error() {}, warn() {} },
    location: { hash: '#' + path, reload: () => reloads++ },
    document: {
      readyState: 'loading',
      getElementById: id => id === 'view' ? view : null,
      querySelectorAll: () => [],
      addEventListener: (event, callback) => { events[event] = callback; },
    },
    window: { scrollTo() {}, addEventListener: (event, callback) => { events[event] = callback; } },
    setTimeout: callback => { timers.set(++nextTimer, callback); return nextTimer; },
    clearTimeout: id => timers.delete(id),
    store: { get: key => state[key], set: (key, value) => { state[key] = value; } },
    sb: { rpc: async () => ({ data: false }) },
    lucide: { createIcons() {} },
  });
  const run = code => vm.runInContext(code, context);
  run(source('pageLoad'));
  run(source('router'));
  return {
    context, view, state, timers, events, run, reloads: () => reloads,
    fireTimers() {
      const callbacks = [...timers.values()];
      timers.clear();
      callbacks.forEach(callback => callback());
    },
  };
}

function loadApp(h, { initAuth = async () => {}, loadConfig = async () => ({}),
  importModule = async () => ({}) } = {}) {
  Object.assign(h.context, {
    initAuth, loadConfig, __loadModule: importModule, getAuthRedirectRoute: () => null,
    loadHomeBooks: async () => [], safeMarked: value => value, h: value => value,
    renderHomeBookCard: () => '', isPwaMobile: () => false,
    registerAuthRoutes: () => h.run("route('/login', () => '<form>登录表单</form>')"),
  });
  for (const name of ['bindNotificationEvents', 'clearPasswordRecoveryPending',
    'replaceAuthRedirectRoute', 'bindAccessEvents', 'bindAuthEvents', 'initPuzzleCaptcha',
    'refreshCaptcha', 'registerMemberSystemInfoRoutes', 'initPwaShell', 'syncPwaShell',
    'applyPwaMode', 'registerPwaServiceWorker', 'bindUploadHandlers', 'bindAuthFeedback']) {
    h.context[name] = () => {};
  }
  h.run(source('app').replace(/\bimport\(/g, '__loadModule('));
}

test('pending route data shows loading, then slow feedback, and can still succeed', async () => {
  const h = harness();
  const pending = deferred();
  h.context.pending = pending.promise;
  h.run("route('/', () => pending)");
  const render = h.run('router.render()');
  assert.match(h.view.innerHTML, /正在加载页面/);
  h.fireTimers();
  assert.match(h.view.innerHTML, /仍在等待数据/);
  assert.match(h.view.innerHTML, /page-reload/);
  pending.resolve('<p>首页内容</p>');
  await render;
  assert.equal(h.view.innerHTML, '<p>首页内容</p>');
  assert.equal(h.timers.size, 0);
});

test('failed route data shows a persistent reload action without exposing raw error text', async () => {
  const h = harness();
  h.run("route('/', async () => { throw Error('<private-response>'); })");
  await h.run('router.render()');
  assert.match(h.view.innerHTML, /页面暂时加载失败/);
  assert.match(h.view.innerHTML, /page-reload/);
  assert.doesNotMatch(h.view.innerHTML, /private-response/);
  assert.equal(h.timers.size, 0);
});

test('late data and old slow timers cannot replace the newly selected route', async () => {
  for (const reject of [false, true]) {
    const h = harness();
    const pending = deferred();
    h.context.pending = pending.promise;
    h.run("route('/', () => pending); route('/login', () => '<form>登录</form>')");
    const oldRender = h.run('router.render()');
    const oldTimer = [...h.timers.values()][0];
    h.context.location.hash = '#/login';
    await h.run('router.render()');
    oldTimer();
    if (reject) pending.reject(Error('old request failed'));
    else pending.resolve('<p>过时首页</p>');
    await oldRender;
    assert.equal(h.view.innerHTML, '<form>登录</form>');
  }
});

test('protected routes still redirect anonymous users before invoking their handlers', async () => {
  const h = harness('/member');
  h.run("route('/member', () => { throw Error('must not execute'); })");
  await h.run('router.render()');
  assert.equal(h.context.location.hash, '#/login?redirect=%2Fmember');
  assert.equal(h.timers.size, 0);
});

test('late admin permission checks cannot overwrite another route', async () => {
  const h = harness('/admin');
  const profile = deferred();
  h.state.user = { id: 'test-user' };
  h.context.sb.from = () => ({ select: () => ({ eq: () => ({ single: () => profile.promise }) }) });
  h.run("route('/admin', () => '<p>后台</p>'); route('/login', () => '<form>登录</form>')");
  const oldRender = h.run('router.render()');
  h.context.location.hash = '#/login';
  await h.run('router.render()');
  profile.resolve({ data: { role: 'member' } });
  await oldRender;
  assert.equal(h.view.innerHTML, '<form>登录</form>');
});

test('initial module failure renders an error page without an undefined toast call', async () => {
  const h = harness('/books');
  let imports = 0;
  loadApp(h, { importModule: async () => {
    imports++;
    if (imports === 1) throw Error('module unavailable');
    h.run("route('/books', () => '<p>书库</p>')");
    return {};
  } });
  await h.events.DOMContentLoaded();
  assert.match(h.view.innerHTML, /页面暂时加载失败/);
  assert.match(h.view.innerHTML, /page-reload/);
  await h.run('renderCurrentRoute()');
  assert.equal(imports, 2);
  assert.equal(h.view.innerHTML, '<p>书库</p>');
});

test('late module failure cannot erase a login page opened while loading', async () => {
  const h = harness('/books');
  const module = deferred();
  loadApp(h, { importModule: () => module.promise });
  const startup = h.events.DOMContentLoaded();
  await flush();
  h.context.location.hash = '#/login';
  h.events.hashchange();
  await flush();
  module.reject(Error('module unavailable'));
  await startup;
  assert.match(h.view.innerHTML, /登录表单/);
  assert.doesNotMatch(h.view.innerHTML, /页面暂时加载失败/);
});

test('protected startup shows waiting feedback while public login stays available', async () => {
  const h = harness('/member');
  const auth = deferred();
  loadApp(h, { initAuth: () => auth.promise });
  const startup = h.events.DOMContentLoaded();
  assert.match(h.view.innerHTML, /正在加载页面/);
  h.context.location.hash = '#/login';
  h.events.hashchange();
  await flush();
  assert.match(h.view.innerHTML, /登录表单/);
  auth.resolve();
  await startup;
  assert.match(h.view.innerHTML, /登录表单/);
});

test('public login still renders without waiting for session restoration', async () => {
  const h = harness('/login');
  const auth = deferred();
  loadApp(h, { initAuth: () => auth.promise });
  await h.events.DOMContentLoaded();
  assert.match(h.view.innerHTML, /登录表单/);
  auth.resolve();
  await flush();
});

test('reload action runs once and does not submit a login or repeat data requests', async () => {
  const h = harness('/login');
  loadApp(h);
  await h.events.DOMContentLoaded();
  const button = { disabled: false, textContent: '' };
  const event = { target: { closest: selector => selector.includes('page-reload') ? button : null } };
  h.events.click(event);
  h.events.click(event);
  assert.equal(h.reloads(), 1);
  assert.equal(button.disabled, true);
});

test('home queries propagate failures, preserve config, and only fall back for empty results', async () => {
  const h = harness();
  let responses = [];
  let requests = 0;
  h.context.sb.from = () => {
    requests++;
    const query = { then: (resolve, reject) => Promise.resolve(responses.shift()).then(resolve, reject) };
    for (const method of ['select', 'not', 'order', 'limit', 'in']) query[method] = () => query;
    return query;
  };
  h.run(source('data'));
  const error = new Error('unavailable');
  h.state.config = { group_rules: 'previous value' };
  responses = [{ data: null, error }];
  await assert.rejects(h.run('loadConfig()'), /unavailable/);
  assert.equal(h.state.config.group_rules, 'previous value');
  requests = 0;
  responses = [{ data: null, error }];
  await assert.rejects(h.run('loadHomeBooks()'), /unavailable/);
  assert.equal(requests, 1);
  responses = [{ data: [] }, { data: null, error }];
  await assert.rejects(h.run('loadHomeBooks()'), /unavailable/);
  responses = [{ data: [] }, { data: [{ id: 1 }] }];
  assert.equal((await h.run('loadHomeBooks()'))[0].id, 1);
});
