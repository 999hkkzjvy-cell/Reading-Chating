import { route, router } from './router.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { esc, h } from './utils.js';

export function registerProfileRoutes() {
  route('/profile/edit', () => {
    const profile = store.get('profile');
    if (!profile) return '';
    const ownPage = '#/user/' + store.get('user')?.id;
    return `
      <div class="container section" style="max-width:560px;">
        <h2 style="margin-bottom:var(--space-3);">编辑资料</h2>
        <div class="card"><div class="card-body">
          <form id="profile-form">
            <div class="form-group"><label>显示名称</label><input type="text" name="display_name" value="${esc(profile.display_name || '')}" required></div>
            <div class="form-group"><label>个人简介</label><textarea name="bio">${h(profile.bio || '')}</textarea></div>
            <div class="form-group"><label>微信号</label><input type="text" name="wechat_id" value="${esc(profile.wechat_id || '')}"></div>
            <div class="form-group"><label>所在城市</label><input type="text" name="city" value="${esc(profile.city || '')}" placeholder="北京"></div>
            <div class="form-group"><label>头像</label>
              <div class="avatar-edit-row">
                <div class="avatar-edit-preview" id="avatar-edit-preview">
                  ${profile.avatar_url ? `<img src="${profile.avatar_url}" alt="">` : '<i data-lucide="user"></i>'}
                </div>
                <div>
                  <input type="file" id="avatar-file-input" accept="image/*">
                  <input type="url" name="avatar_url" value="${esc(profile.avatar_url || '')}" placeholder="或粘贴图片链接 https://...">
                </div>
              </div>
            </div>
            <button type="submit" class="btn btn-primary">保存</button>
            <a href="${ownPage}" class="btn btn-ghost">取消</a>
          </form>
        </div></div>
      </div>
    `;
  });
}

export function bindProfileEvents() {
  document.addEventListener('submit', async e => {
    if (e.target.id === 'profile-form') {
      e.preventDefault();
      const fd = new FormData(e.target);
      const updates = {
        display_name: fd.get('display_name'),
        bio: fd.get('bio'),
        wechat_id: fd.get('wechat_id'),
        city: fd.get('city'),
        avatar_url: fd.get('avatar_url'),
        updated_at: new Date().toISOString()
      };
      const { error } = await sb.from('profiles').update(updates).eq('id', store.get('user').id);
      if (error) {
        toast('保存失败：' + error.message, 'error');
        return;
      }
      store.set('profile', { ...store.get('profile'), ...updates });
      toast('资料已更新');
      const ownPage = '/user/' + store.get('user')?.id;
      router.navigate(ownPage);
    }
  });
}
