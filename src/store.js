export const store = {
  _state: {
    user: null,
    profile: null,
    member: null,
    isAdmin: false,
    books: [],
    events: [],
    config: {}
  },
  _listeners: {},
  get(k) {
    return this._state[k];
  },
  set(k, v) {
    this._state[k] = v;
    (this._listeners[k] || []).forEach(fn => fn(v));
  },
  on(k, fn) {
    (this._listeners[k] = this._listeners[k] || []).push(fn);
  }
};
