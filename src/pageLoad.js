let activeLoad = null;

function loadingMarkup(slow = false) {
  return `
    <section class="container section">
      <div class="empty-state" role="status">
        <p>${slow ? '页面加载较慢，仍在等待数据。' : '正在加载页面…'}</p>
        ${slow ? '<p>可以切换网络后继续等待，或重新加载页面。</p><button type="button" class="btn btn-outline" data-action="page-reload">重新加载页面</button>' : ''}
      </div>
    </section>
  `;
}

// One lifecycle covers module loading, access checks and the route's data.
// Timers only update feedback; they never cancel or retry Auth requests.
export function beginPageLoad(path) {
  activeLoad?.cancel();
  const view = document.getElementById('view');
  let settled = false;
  let timer;
  const load = {
    isCurrent: () => activeLoad === load && !settled &&
      (location.hash.slice(1) || '/') === path,
    cancel() {
      settled = true;
      clearTimeout(timer);
    },
    complete(html) {
      if (!load.isCurrent()) return false;
      load.cancel();
      if (view) view.innerHTML = html;
      return true;
    },
    fail(error) {
      if (!load.isCurrent()) return false;
      console.error('Page load failed:', error);
      return load.complete(`
        <section class="container section">
          <div class="empty-state" role="alert">
            <p>页面暂时加载失败，请检查网络后重试。</p>
            <button type="button" class="btn btn-outline" data-action="page-reload">重新加载页面</button>
          </div>
        </section>
      `);
    },
  };
  activeLoad = load;
  if (view) view.innerHTML = loadingMarkup();
  timer = setTimeout(() => {
    if (load.isCurrent() && view) view.innerHTML = loadingMarkup(true);
  }, 12000);
  return load;
}
