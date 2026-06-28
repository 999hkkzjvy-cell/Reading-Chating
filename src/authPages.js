import {
  checkLoginRateLimit,
  recordLoginAttempt,
  resetPassword,
  signIn,
  signUp,
  updatePassword
} from './auth.js';
import { isCaptchaVerified, refreshCaptcha } from './captcha.js';
import { route, router } from './router.js';

export function registerAuthRoutes() {
  route('/login', () => {
    return `
      <div class="container auth-page">
        <div class="card">
          <h2>登录</h2>
          <form id="login-form" autocomplete="off">
            <div class="form-group"><label>邮箱</label><input type="email" name="email" required></div>
            <div class="form-group"><label>密码</label><input type="password" name="password" required minlength="6"></div>
            <div class="captcha-row">
              <div class="puzzle-box">
                <div class="pz-bg"></div>
                <div class="pz-gap"></div>
                <div class="pz-piece"></div>
                <div class="pz-status">拖动滑块使拼图对齐缺口</div>
              </div>
              <div class="puzzle-slider">
                <div class="pz-track"></div>
                <div class="pz-handle"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg></div>
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
          <div id="login-error" style="color:var(--color-danger);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
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
  document.addEventListener('submit', async e => {
    if (e.target.id === 'login-form') {
      e.preventDefault();
      const limit = checkLoginRateLimit();
      if (limit.blocked) {
        document.getElementById('login-error').textContent = `登录尝试次数过多，请 ${limit.remaining} 秒后重试。`;
        return;
      }
      if (!isCaptchaVerified()) {
        document.getElementById('login-error').textContent = '请完成滑动验证。';
        return;
      }
      const fd = new FormData(e.target);
      try {
        await signIn(fd.get('email'), fd.get('password'));
        recordLoginAttempt(true);
        const redirect = location.hash.includes('redirect=') ? decodeURIComponent(location.hash.split('redirect=')[1]) : '/';
        router.navigate(redirect);
      } catch (err) {
        recordLoginAttempt(false);
        refreshCaptcha();
        document.getElementById('login-error').textContent = err.message;
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
        await updatePassword(fd.get('password'));
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
