import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = name => readFileSync(new URL(`../src/${name}.js`, import.meta.url), 'utf8');
class Element extends EventTarget {
  constructor(width = 340) {
    super();
    Object.assign(this, { clientWidth: width, offsetWidth: width, style: {}, dataset: {}, children: {}, attrs: {}, isConnected: true, textContent: '' });
    const classes = new Set();
    this.classList = { add: (...xs) => xs.forEach(x => classes.add(x)), remove: (...xs) => xs.forEach(x => classes.delete(x)), contains: x => classes.has(x) };
  }
  querySelector(key) { return this.children[key] ?? null; }
  setAttribute(key, value) { this.attrs[key] = value; }
  removeAttribute(key) { delete this.attrs[key]; }
  focus() { this.focused = true; }
  setPointerCapture(id) { this.captured = id; }
  hasPointerCapture(id) { return this.captured === id; }
  releasePointerCapture() { this.captured = null; }
  getBoundingClientRect() { return { width: this.offsetWidth }; }
  emit(type, fields = {}) {
    const e = new Event(type, { cancelable: true });
    Object.assign(e, { pointerId: 1, isPrimary: true, button: 0, clientX: 0 }, fields);
    this.dispatchEvent(e);
    return e;
  }
}

function puzzleHarness() {
  const document = new Element(), window = new Element();
  const observers = [];
  const context = vm.createContext({
    document, window, Event, AbortController, Math,
    setTimeout() { throw new Error('Puzzle must not schedule delayed resets'); },
    ResizeObserver: class {
      constructor(fn) { this.fn = fn; observers.push(this); }
      observe() {}
      disconnect() { this.disconnected = true; }
    },
  });
  vm.runInContext(source('captcha').replaceAll('export function ', 'function '), context);
  const run = code => vm.runInContext(code, context);
  function mount(width = 340) {
    if (document.children['.puzzle-box']) document.children['.puzzle-box'].isConnected = false;
    const box = new Element(width), slider = new Element(width), handle = new Element(40);
    for (const key of ['.pz-piece', '.pz-gap', '.pz-bg', '.pz-status']) box.children[key] = new Element();
    slider.children['.pz-handle'] = handle;
    slider.children['.pz-track'] = new Element();
    document.children = { '.puzzle-box': box, '.puzzle-slider': slider };
    run('initPuzzleCaptcha()');
    const target = () => parseFloat(box.children['.pz-gap'].style.left) - 16;
    return { box, slider, handle, target, drag(delta = target()) {
      handle.emit('pointerdown');
      handle.emit('pointermove', { clientX: delta });
      handle.emit('pointerup', { clientX: delta });
    } };
  }
  return { document, window, observers, run, mount };
}

test('refreshing repeatedly still verifies exactly once on the visible puzzle', () => {
  const h = puzzleHarness(), p = h.mount();
  let successes = 0;
  p.box.addEventListener('captcha-verified', () => successes++);
  for (let i = 0; i < 20; i++) h.run('refreshCaptcha()');
  p.drag();
  assert.equal(h.run('isCaptchaVerified()'), true);
  assert.equal(p.box.children['.pz-status'].textContent, '✓ 验证通过');
  assert.equal(successes, 1);
  assert.ok(h.observers.slice(0, -1).every(o => o.disconnected));
});

test('route re-entry disposes old elements and updates the new puzzle', () => {
  const h = puzzleHarness(), old = h.mount();
  old.handle.emit('pointerdown');
  const current = h.mount();
  old.drag();
  assert.equal(h.run('isCaptchaVerified()'), false);
  current.drag();
  assert.equal(current.box.children['.pz-status'].textContent, '✓ 验证通过');
  assert.equal(old.box.classList.contains('success'), false);
  current.box.isConnected = false;
  h.document.children = {};
  h.run('initPuzzleCaptcha()');
  assert.equal(h.run('isCaptchaVerified()'), false);
});

test('failed drops allow immediate retry without changing the gap or locking', () => {
  const h = puzzleHarness(), p = h.mount(), target = p.target();
  for (let i = 0; i < 5; i++) p.drag(0);
  assert.equal(p.target(), target);
  assert.equal(p.slider.classList.contains('locked'), false);
  assert.equal(h.run('isCaptchaVerified()'), false);
  p.drag(target + 9);
  assert.equal(h.run('isCaptchaVerified()'), true);
  assert.equal(p.box.children['.pz-piece'].style.left, p.box.children['.pz-gap'].style.left);
});

test('pointer cancellation, capture loss and window blur allow a clean retry', () => {
  for (const kind of ['pointercancel', 'lostpointercapture', 'blur']) {
    const h = puzzleHarness(), p = h.mount();
    p.handle.emit('pointerdown');
    p.handle.emit('pointermove', { clientX: p.target() });
    (kind === 'blur' ? h.window : p.handle).emit(kind);
    p.handle.emit('pointerup', { clientX: p.target() });
    assert.equal(h.run('isCaptchaVerified()'), false, kind);
    assert.equal(p.handle.style.left, '2px');
    p.drag();
    assert.equal(h.run('isCaptchaVerified()'), true, kind);
  }
});

test('secondary touch cannot move or finish the primary drag', () => {
  const h = puzzleHarness(), p = h.mount();
  p.handle.emit('pointerdown');
  p.handle.emit('pointermove', { pointerId: 2, clientX: p.target() });
  p.handle.emit('pointerup', { pointerId: 2, clientX: p.target() });
  assert.equal(p.handle.style.left, '2px');
  assert.equal(h.run('isCaptchaVerified()'), false);
  p.handle.emit('pointerup', { clientX: p.target() });
  assert.equal(h.run('isCaptchaVerified()'), true);
});

test('keyboard supports precise movement and confirmation without form submission', () => {
  const h = puzzleHarness(), p = h.mount();
  for (let i = 0; i < Math.round(p.target() / 2); i++) p.handle.emit('keydown', { key: 'ArrowRight' });
  assert.equal(h.run('isCaptchaVerified()'), false);
  const e = p.handle.emit('keydown', { key: 'Enter' });
  assert.equal(e.defaultPrevented, true);
  assert.equal(h.run('isCaptchaVerified()'), true);
});

test('resize during dragging resets safely; narrow gaps remain reachable', () => {
  const h = puzzleHarness(), p = h.mount();
  p.handle.emit('pointerdown');
  p.box.clientWidth = p.slider.clientWidth = p.slider.offsetWidth = 180;
  h.observers.at(-1).fn();
  p.handle.emit('pointerup', { clientX: p.target() });
  assert.equal(h.run('isCaptchaVerified()'), false);
  assert.ok(p.target() <= 180 - 40 - 4);
  p.drag();
  assert.equal(h.run('isCaptchaVerified()'), true);
  p.box.clientWidth = 200;
  h.observers.at(-1).fn();
  assert.equal(h.run('isCaptchaVerified()'), true);
});

function loginHarness(signIn, verified = true) {
  const handlers = {}, attempts = [], navigations = [];
  const error = new Element(), btn = new Element(), handle = new Element(), form = new Element();
  form.id = 'login-form';
  form.parentElement = { querySelector: () => error };
  form.children = { 'button[type="submit"]': btn, '.pz-handle': handle };
  const context = vm.createContext({
    document: { addEventListener: (type, fn) => handlers[type] = fn },
    location: { hash: '#/login?redirect=%2Fmember' }, URLSearchParams,
    FormData: class { get(key) { return key === 'email' ? ' user@example.test ' : 'test-only'; } },
    checkLoginRateLimit: () => ({ blocked: false }), recordLoginAttempt: ok => attempts.push(ok),
    isCaptchaVerified: () => verified, signIn,
    router: { navigate: path => navigations.push(path) },
  });
  vm.runInContext(source('authPages').replace(/import[\s\S]*?from '[^']+';\n/g, '').replaceAll('export function ', 'function '), context);
  vm.runInContext('bindAuthEvents()', context);
  return { form, error, btn, handle, attempts, navigations, handlers,
    submit: () => handlers.submit({ target: form, preventDefault() {} }) };
}

test('pending login prevents duplicate requests and restores controls after failure', async () => {
  let reject, requests = 0;
  const h = loginHarness(email => {
    requests++;
    assert.equal(email, 'user@example.test');
    return new Promise((resolve, no) => reject = no);
  });
  const first = h.submit();
  assert.equal(h.btn.disabled, true);
  assert.equal(h.btn.textContent, '登录中…');
  await h.submit();
  assert.equal(requests, 1);
  reject({ code: 'invalid_credentials' });
  await first;
  assert.deepEqual(h.attempts, [false]);
  assert.match(h.error.textContent, /邮箱或密码不正确/);
  assert.equal(h.btn.disabled, false);
  assert.equal(h.form.attrs['aria-busy'], undefined);
});

test('network, service, email and rate-limit failures never count as bad credentials', async () => {
  for (const err of [{ name: 'AuthRetryableFetchError' }, { status: 503 }, { code: 'email_not_confirmed' }, { status: 429 }]) {
    const h = loginHarness(async () => { throw err; });
    await h.submit();
    assert.deepEqual(h.attempts, []);
    assert.notEqual(h.error.textContent, '');
    // A retry reaches signIn without resetting the completed captcha.
    await h.submit();
    assert.equal(h.btn.disabled, false);
  }
});

test('late results do not modify another route or navigate away from it', async () => {
  for (const success of [false, true]) {
    let resolve, reject;
    const h = loginHarness(() => new Promise((yes, no) => { resolve = yes; reject = no; }));
    const pending = h.submit();
    h.form.isConnected = false;
    if (success) resolve(); else reject({ code: 'invalid_credentials' });
    await pending;
    assert.equal(h.error.textContent, '');
    assert.deepEqual(h.navigations, []);
  }
});

test('successful login follows original redirect and clears local failures', async () => {
  const h = loginHarness(async () => {});
  await h.submit();
  assert.deepEqual(h.attempts, [true]);
  assert.deepEqual(h.navigations, ['/member']);
});

test('missing captcha blocks requests and completing it clears only its own error', async () => {
  let requests = 0;
  const h = loginHarness(async () => requests++, false);
  await h.submit();
  assert.equal(requests, 0);
  assert.equal(h.handle.focused, true);
  h.handlers['captcha-verified']({ target: { closest: () => h.form } });
  assert.equal(h.error.textContent, '');
  h.error.textContent = '邮箱或密码不正确';
  h.handlers['captcha-verified']({ target: { closest: () => h.form } });
  assert.equal(h.error.textContent, '邮箱或密码不正确');
});

function rateHarness() {
  let now = 1000000;
  const values = new Map();
  const storage = { getItem: k => values.get(k), setItem: (k, v) => values.set(k, v), removeItem: k => values.delete(k) };
  const context = vm.createContext({ sessionStorage: storage, Date: { now: () => now } });
  const auth = source('auth');
  vm.runInContext(auth.slice(auth.indexOf('export function checkLoginRateLimit'), auth.indexOf('export async function signIn')).replaceAll('export function ', 'function '), context);
  return { values, storage, tick: ms => now += ms, run: code => vm.runInContext(code, context) };
}

test('local cooldown escalates, expires, and forgets failures after inactivity', () => {
  const h = rateHarness();
  for (let i = 0; i < 3; i++) h.run('recordLoginAttempt(false)');
  assert.equal(h.run('checkLoginRateLimit().remaining'), 15);
  h.run('recordLoginAttempt(false)');
  assert.equal(h.run('checkLoginRateLimit().count'), 3);
  h.tick(15001);
  assert.equal(h.run('checkLoginRateLimit().blocked'), false);
  h.run('recordLoginAttempt(false)');
  assert.equal(h.run('checkLoginRateLimit().remaining'), 15);
  h.tick(15001);
  h.run('recordLoginAttempt(false)');
  assert.equal(h.run('checkLoginRateLimit().remaining'), 60);
  h.tick(900001);
  assert.equal(h.run('checkLoginRateLimit().count'), 0);
});

test('malformed or unavailable storage does not break login', () => {
  const h = rateHarness();
  for (const value of ['null', '{}', 'bad-json', '{"count":null,"until":0}']) {
    h.values.set('login_attempts', value);
    assert.equal(h.run('checkLoginRateLimit().blocked'), false);
    h.run('recordLoginAttempt(false)');
    assert.equal(h.run('checkLoginRateLimit().count'), 1);
  }
  for (const key of Object.keys(h.storage)) h.storage[key] = () => { throw new Error('unavailable'); };
  assert.doesNotThrow(() => h.run('checkLoginRateLimit(); recordLoginAttempt(false); recordLoginAttempt(true)'));
});
