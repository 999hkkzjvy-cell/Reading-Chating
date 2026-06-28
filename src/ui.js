export function toast(msg, type = 'success') {
  const el = document.createElement('div');
  el.className = `toast toast-${type}`;
  el.textContent = msg;
  document.getElementById('toast-container').appendChild(el);
  setTimeout(() => {
    el.style.opacity = '0';
    el.style.transition = 'opacity 0.3s';
    setTimeout(() => el.remove(), 300);
  }, 3000);
}

export function showModal(title, contentHtml, onClose) {
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay';
  overlay.innerHTML = `<div class="modal">
    <div class="modal-header"><h3>${title}</h3><button id="modal-close-btn"><i data-lucide="x"></i></button></div>
    <div class="modal-body">${contentHtml}</div>
  </div>`;
  document.getElementById('modal-container').appendChild(overlay);
  lucide.createIcons();
  overlay.querySelector('#modal-close-btn').onclick = () => {
    overlay.remove();
    if (onClose) onClose();
  };
  // Only close via X button; clicking outside / pressing Enter won't close.
  overlay.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && e.target.tagName !== 'TEXTAREA') {
      e.preventDefault();
      e.stopPropagation();
    }
  });
  return overlay;
}
