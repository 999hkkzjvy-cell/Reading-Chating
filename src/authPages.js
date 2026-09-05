import {
  checkLoginRateLimit,
  completePasswordReset,
  recordLoginAttempt,
  resetPassword,
  signIn,
  signUp,
} from './auth.js';
import { isCaptchaVerified } from './captcha.js';
import { route, router } from './router.js';

let loginPending = false;

function loginErrorMessage(err) {
  if (err?.code === 'invalid_credentials') return '邮箱或密码不正确，请检查后重试。';
  if (err?.code === 'email_not_confirmed') return '邮箱尚未验证，请先点击注册邮件中的验证链接。';
  if (err?.status === 429 || err?.code === 'over_request_rate_limit') return '登录请求过于频繁，请稍后重试。';
  if (err?.name === 'AuthRetryableFetchError' || err?.code === 'request_timeout' ||
      err?.status >= 500 || err?.name === 'TypeError') {
    return '网络连接或登录服务暂时异常，请稍后重试。';
  }
  return '暂时无法完成登录，请稍后重试。';
}

export function registerAuthRoutes() {
  route('/login', () => {
    return `
      <div class="container auth-page">
        <div class="card">
          <h2>登录</h2>
          <form id="login-form">
            <div class="form-group"><label for="login-email">邮箱</label><input id="login-email" type="email" name="email" autocomplete="username" required></div>
            <div class="form-group"><label for="login-password">密码</label><input id="login-password" type="password" name="password" autocomplete="current-password" required minlength="6"></div>
            <div class="captcha-row">
              <div class="puzzle-box">
                <div class="pz-bg"></div>
                <div class="pz-gap"></div>
                <div class="pz-piece"></div>
                <div class="pz-status" id="captcha-status" role="status" aria-live="polite">拖动滑块使拼图对齐缺口</div>
              </div>
              <div class="puzzle-slider">
                <div class="pz-track"></div>
                <div class="pz-handle" role="slider" tabindex="0" aria-label="拼图验证，左右方向键调整，回车确认" aria-describedby="captcha-status" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"><svg aria-hidden="true" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg></div>
              </div>
              <button type="button" class="captcha-refresh" data-action="captcha-refresh">🔄 换一张</button>
            </div>
            <div style="display:flex;gap:var(--space-2);">
              <button type="submit" class="btn btn-primary" style="flex:1">登录</button>
              <a href="#/register" class="btn btn-primary" style="flex:1;text-align:center;">注册</a>
            </div>
            <div style="text-align:center;margin-top:var(--space-2);">
              <a href="#/forgot-password" style="font-size:0.9rem;color:var(--color-text-2);">忘记密码？</a>
            </div>
          </form>
          <div id="login-error" role="alert" style="color:var(--color-danger);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
        </div>
      </div>
    `;
  });

  route('/register', () => {
    return `
      <div class="container auth-page">
        <div class="card">
          <h2>注册</h2>
          <form id="register-form">
            <div class="form-group"><label>显示名称</label><input type="text" name="displayName" required></div>
            <div class="form-group"><label>邮箱</label><input type="email" name="email" required></div>
            <div class="form-group"><label>密码（至少6位）</label><input type="password" name="password" required minlength="6"></div>
            <button type="submit" class="btn btn-primary" style="width:100%">注册</button>
          </form>
          <div class="alt-link">已有账号？<a href="#/login">去登录</a></div>
          <div id="reg-error" style="color:var(--color-danger);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
        </div>
      </div>
    `;
  });

  route('/forgot-password', () => {
    return `
      <div class="container auth-page">
        <div class="card">
          <h2>忘记密码</h2>
          <p style="text-align:center;color:var(--color-text-2);font-size:0.9rem;margin-bottom:var(--space-3);">
            输入注册邮箱，我们将发送重置密码链接。
          </p>
          <form id="forgot-form">
            <div class="form-group"><label>邮箱</label><input type="email" name="email" required></div>
            <button type="submit" class="btn btn-primary" style="width:100%">发送重置邮件</button>
          </form>
          <div class="alt-link"><a href="#/login">← 返回登录</a></div>
          <div id="forgot-error" style="color:var(--color-danger);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
          <div id="forgot-msg" style="color:var(--color-success);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
        </div>
      </div>
    `;
  });

  route('/reset-password', () => {
    return `
      <div class="container auth-page">
        <div class="card">
          <h2>重置密码</h2>
          <p style="text-align:center;color:var(--color-text-2);font-size:0.9rem;margin-bottom:var(--space-3);">
            请输入你的新密码。
          </p>
          <form id="reset-form">
            <div class="form-group"><label>新密码（至少6位）</label><input type="password" name="password" required minlength="6"></div>
            <button type="submit" class="btn btn-primary" style="width:100%">重置密码</button>
          </form>
          <div class="alt-link"><a href="#/login">← 返回登录</a></div>
          <div id="reset-error" style="color:var(--color-danger);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
          <div id="reset-msg" style="color:var(--color-success);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
        </div>
      </div>
    `;
  });
}

export function bindAuthEvents() {
  document.addEventListener('captcha-verified', e => {
    const form = e.target.closest('#login-form');
    const error = form?.parentElement.querySelector('#login-error');
    if (error?.dataset.captchaRequired === 'true') {
      error.textContent = '';
      delete error.dataset.captchaRequired;
    }
  });
  document.addEventListener('submit', async e => {
    if (e.target.id === 'login-form') {
      e.preventDefault();
      const form = e.target;
      const error = form.parentElement.querySelector('#login-error');
      if (loginPending) return;
      error.textContent = '';
      delete error.dataset.captchaRequired;
      const limit = checkLoginRateLimit();
      if (limit.blocked) {
        error.textContent = `登录尝试次数过多，请 ${limit.remaining} 秒后重试。`;
        return;
      }
      if (!isCaptchaVerified()) {
        error.textContent = '请先完成拼图验证。';
        error.dataset.captchaRequired = 'true';
        form.querySelector('.pz-handle').focus();
        return;
      }
      const fd = new FormData(form);
      const btn = form.querySelector('button[type="submit"]');
      const redirect = new URLSearchParams(location.hash.split('?')[1] || '').get('redirect') || '/';
      loginPending = true;
      btn.disabled = true;
      btn.textContent = '登录中…';
      form.setAttribute('aria-busy', 'true');
      try {
        await signIn(fd.get('email').trim(), fd.get('password'));
        recordLoginAttempt(true);
        if (form.isConnected) router.navigate(redirect);
      } catch (err) {
        // Only rejected credentials count; network/service errors are not bad passwords.
        if (err?.code === 'invalid_credentials') recordLoginAttempt(false);
        if (form.isConnected) {
          error.textContent = loginErrorMessage(err);
          const retryLimit = checkLoginRateLimit();
          if (retryLimit.blocked) error.textContent += ` 请 ${retryLimit.remaining} 秒后重试。`;
        }
      } finally {
        loginPending = false;
        btn.disabled = false;
        btn.textContent = '登录';
        form.removeAttribute('aria-busy');
      }
    }

    if (e.target.id === 'register-form') {
      e.preventDefault();
      const fd = new FormData(e.target);
      try {
        await signUp(fd.get('email'), fd.get('password'), fd.get('displayName'));
        router.navigate('/login');
      } catch (err) {
        document.getElementById('reg-error').textContent = err.message;
      }
    }

    if (e.target.id === 'forgot-form') {
      e.preventDefault();
      const fd = new FormData(e.target);
      const btn = e.target.querySelector('button[type="submit"]');
      btn.disabled = true;
      btn.textContent = '发送中...';
      try {
        await resetPassword(fd.get('email'));
        document.getElementById('forgot-msg').textContent = '密码重置邮件已发送，请检查邮箱。如果未收到，请查看垃圾邮件。';
        document.getElementById('forgot-error').textContent = '';
      } catch (err) {
        document.getElementById('forgot-error').textContent = err.message;
        document.getElementById('forgot-msg').textContent = '';
      } finally {
        btn.disabled = false;
        btn.textContent = '发送重置邮件';
      }
    }

    if (e.target.id === 'reset-form') {
      e.preventDefault();
      const fd = new FormData(e.target);
      const btn = e.target.querySelector('button[type="submit"]');
      btn.disabled = true;
      btn.textContent = '重置中...';
      try {
        await completePasswordReset(fd.get('password'));
        document.getElementById('reset-msg').textContent = '密码已重置，即将跳转登录页...';
        document.getElementById('reset-error').textContent = '';
        setTimeout(() => router.navigate('/login'), 1500);
      } catch (err) {
        document.getElementById('reset-error').textContent = err.message;
        document.getElementById('reset-msg').textContent = '';
      } finally {
        btn.disabled = false;
        btn.textContent = '重置密码';
      }
    }
  });
}
