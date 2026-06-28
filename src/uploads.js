import { sb } from './supabaseClient.js';
import { toast } from './ui.js';

function updateCoverPreview(url) {
  const preview = document.getElementById('cover-preview');
  if (!preview) return;
  preview.innerHTML = '';
  if (url) {
    const img = document.createElement('img');
    img.src = url;
    img.alt = '';
    img.onerror = () => {
      preview.textContent = '?';
    };
    preview.appendChild(img);
  } else {
    preview.innerHTML = '<i data-lucide="image" style="width:28px;height:28px;color:var(--color-text-3);"></i>';
    lucide.createIcons();
  }
}

function updatePosterPreview(url) {
  const preview = document.getElementById('poster-preview');
  if (!preview) return;
  preview.innerHTML = '';
  if (url) {
    const img = document.createElement('img');
    img.src = url;
    img.alt = '';
    img.onerror = () => {
      preview.textContent = '?';
    };
    preview.appendChild(img);
  } else {
    preview.innerHTML = '<i data-lucide="image" style="width:28px;height:28px;color:var(--color-text-3);"></i>';
    lucide.createIcons();
  }
}

function safeUploadName(fileName, fallback) {
  return fileName.replace(/[^a-zA-Z0-9._-]/g, '').replace(/\.+/g, '.') || fallback;
}

export function bindUploadHandlers() {
  document.addEventListener('input', (e) => {
    if (e.target.id === 'cover-url-input') updateCoverPreview(e.target.value);
    if (e.target.id === 'poster-url-input') updatePosterPreview(e.target.value);
  });

  document.addEventListener('change', async (e) => {
    if (e.target.id !== 'cover-file-input') return;
    const file = e.target.files[0];
    if (!file) return;
    const ext = file.name.split('.').pop();
    const safeName = safeUploadName(file.name, 'cover');
    const path = `${Date.now()}_${safeName}.${ext}`;
    const { error } = await sb.storage.from('covers').upload(path, file);
    if (error) {
      toast('封面上传失败：' + error.message, 'error');
      return;
    }
    const { data: { publicUrl } } = sb.storage.from('covers').getPublicUrl(path);
    const urlInput = document.getElementById('cover-url-input');
    if (urlInput) urlInput.value = publicUrl;
    updateCoverPreview(publicUrl);
    toast('封面上传成功');
  });

  document.addEventListener('change', async (e) => {
    if (e.target.id !== 'poster-file-input') return;
    const file = e.target.files[0];
    if (!file) return;
    const ext = file.name.split('.').pop();
    const safeName = safeUploadName(file.name, 'poster');
    const path = `${Date.now()}_${safeName}.${ext}`;
    const { error } = await sb.storage.from('covers').upload(path, file);
    if (error) {
      toast('海报上传失败：' + error.message, 'error');
      return;
    }
    const { data: { publicUrl } } = sb.storage.from('covers').getPublicUrl(path);
    const urlInput = document.getElementById('poster-url-input');
    if (urlInput) urlInput.value = publicUrl;
    updatePosterPreview(publicUrl);
    toast('海报上传成功');
  });

  document.addEventListener('change', async (e) => {
    if (e.target.id !== 'schedule-pdf-input') return;
    const file = e.target.files[0];
    if (!file) return;
    const ext = file.name.split('.').pop();
    const safeName = safeUploadName(file.name, 'schedule');
    const path = `${Date.now()}_${safeName}.${ext}`;
    const { error } = await sb.storage.from('files').upload(path, file);
    if (error) {
      toast('PDF 上传失败：' + error.message, 'error');
      return;
    }
    const { data: { publicUrl } } = sb.storage.from('files').getPublicUrl(path);
    const urlInput = document.getElementById('schedule-pdf-url');
    const nameEl = document.getElementById('schedule-pdf-name');
    if (urlInput) urlInput.value = publicUrl;
    if (nameEl) nameEl.textContent = '已上传：' + file.name;
    toast('PDF 上传成功');
  });
}
