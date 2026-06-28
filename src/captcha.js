let _pzVerified = false;
let _pzDragging = false;
let _pzGapX = 0;
let _pzFailCount = 0;

const PZ_SHAPE = 'path("M0,6 C0,2 2,0 6,0 L44,0 C48,0 50,2 50,6 L50,18 C50,18 40,15 38,22 C36,29 46,28 50,32 L50,44 C50,48 48,50 44,50 L6,50 C2,50 0,48 0,44 L0,6 Z")';

function randomGradient() {
  const h1 = Math.floor(Math.random() * 360);
  const h2 = (h1 + 30 + Math.floor(Math.random() * 60)) % 360;
  const h3 = (h1 + 120 + Math.floor(Math.random() * 60)) % 360;
  return `linear-gradient(135deg, hsl(${h1},55%,60%), hsl(${h2},65%,50%), hsl(${h3},55%,55%))`;
}

function makePuzzleSvg(boxW, bgGradient, showX) {
  const enc = encodeURIComponent;
  const bgSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${boxW}" height="160"><rect width="${boxW}" height="160" fill="${bgGradient.replace(/#/g, '%23')}"/></svg>`;
  return `<svg viewBox="0 0 50 50" xmlns="http://www.w3.org/2000/svg">
    <defs><clipPath id="pzc"><path d="M0,6 C0,2 2,0 6,0 L44,0 C48,0 50,2 50,6 L50,18 C50,18 40,15 38,22 C36,29 46,28 50,32 L50,44 C50,48 48,50 44,50 L6,50 C2,50 0,48 0,44 L0,6 Z"/></clipPath></defs>
    <image href="data:image/svg+xml,${enc(bgSvg)}" x="${showX}" y="-55" width="${boxW}" height="160" clip-path="url(#pzc)" preserveAspectRatio="none"/>
  </svg>`;
}

export function initPuzzleCaptcha() {
  _pzVerified = false;
  _pzDragging = false;
  const box = document.querySelector('.puzzle-box');
  if (!box) return;
  box.classList.remove('success', 'fail');
  const slider = document.querySelector('.puzzle-slider');
  slider.classList.remove('success', 'locked');
  const status = box.querySelector('.pz-status');
  status.textContent = '拖动滑块使拼图对齐缺口';
  status.style.background = 'rgba(0,0,0,0.4)';

  const bgGradient = randomGradient();
  const boxW = box.clientWidth;

  _pzGapX = Math.floor(boxW * 0.35) + Math.floor(Math.random() * (boxW * 0.3));

  box.querySelector('.pz-bg').style.background = bgGradient;

  const gap = box.querySelector('.pz-gap');
  gap.style.left = _pzGapX + 'px';
  gap.style.clipPath = PZ_SHAPE;
  gap.style.background = 'rgba(0,0,0,0.2)';
  gap.innerHTML = '';

  const pieceStartX = 16;
  const piece = box.querySelector('.pz-piece');
  piece.style.left = pieceStartX + 'px';
  piece.innerHTML = makePuzzleSvg(boxW, bgGradient, -_pzGapX);
  piece.style.clipPath = PZ_SHAPE;

  const handle = slider.querySelector('.pz-handle');
  handle.style.left = '2px';
  slider.querySelector('.pz-track').style.width = '0';
  const handleMax = slider.clientWidth - handle.clientWidth - 4;
  const handleTarget = Math.min(2 + _pzGapX - pieceStartX, handleMax);

  bindPuzzleEvents(box, slider, handle, piece, handleMax, pieceStartX, handleTarget);
}

function bindPuzzleEvents(box, slider, handle, piece, handleMax, pieceStartX, handleTarget) {
  let startX = 0;
  let startLeft = 0;
  const track = slider.querySelector('.pz-track');
  const status = box.querySelector('.pz-status');

  const onStart = (e) => {
    if (_pzVerified || slider.classList.contains('locked')) return;
    _pzDragging = true;
    handle.style.transition = 'none';
    piece.style.transition = 'none';
    track.style.transition = 'none';
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    startX = clientX;
    startLeft = parseFloat(handle.style.left) || 2;
  };
  const onMove = (e) => {
    if (!_pzDragging) return;
    e.preventDefault();
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    let hLeft = startLeft + (clientX - startX);
    hLeft = Math.max(2, Math.min(handleMax, hLeft));
    handle.style.left = hLeft + 'px';
    track.style.width = (hLeft + handle.clientWidth / 2) + 'px';
    const pLeft = pieceStartX + (hLeft - 2);
    piece.style.left = pLeft + 'px';
  };
  const onEnd = () => {
    if (!_pzDragging) return;
    _pzDragging = false;
    handle.style.transition = 'left 0.35s ease';
    piece.style.transition = 'left 0.35s ease';
    track.style.transition = 'width 0.35s ease';
    const hLeft = parseFloat(handle.style.left) || 2;
    const pLeft = pieceStartX + (hLeft - 2);
    const tolerance = 6;

    if (Math.abs(pLeft - _pzGapX) <= tolerance) {
      piece.style.left = _pzGapX + 'px';
      handle.style.left = handleTarget + 'px';
      track.style.width = (handleTarget + handle.clientWidth / 2) + 'px';
      box.classList.add('success');
      slider.classList.add('success');
      status.textContent = '✓ 核验成功';
      box.classList.remove('fail');
      _pzVerified = true;
      _pzFailCount = 0;
    } else {
      _pzFailCount++;
      piece.style.left = pieceStartX + 'px';
      handle.style.left = '2px';
      track.style.width = '0';
      box.classList.add('fail');
      box.classList.remove('success');
      status.textContent = '✗ 核验失败';
      setTimeout(() => {
        if (!_pzVerified) {
          if (_pzFailCount >= 3) {
            lockCaptcha(slider, box);
          } else {
            initPuzzleCaptcha();
          }
        }
      }, 1200);
    }
  };

  handle.removeEventListener('mousedown', onStart);
  handle.removeEventListener('touchstart', onStart);
  document.removeEventListener('mousemove', onMove);
  document.removeEventListener('touchmove', onMove);
  document.removeEventListener('mouseup', onEnd);
  document.removeEventListener('touchend', onEnd);

  handle.addEventListener('mousedown', onStart);
  handle.addEventListener('touchstart', onStart, { passive: false });
  document.addEventListener('mousemove', onMove);
  document.addEventListener('touchmove', onMove, { passive: false });
  document.addEventListener('mouseup', onEnd);
  document.addEventListener('touchend', onEnd);
}

function lockCaptcha(slider, box) {
  slider.classList.add('locked');
  const status = box.querySelector('.pz-status');
  status.textContent = '失败次数过多，请 5 分钟后再试';
  status.style.background = 'rgba(220,53,69,0.85)';
  _pzVerified = false;
  setTimeout(() => {
    _pzFailCount = 0;
    initPuzzleCaptcha();
  }, 300000);
}

export function refreshCaptcha() {
  _pzFailCount = 0;
  initPuzzleCaptcha();
}

export function isCaptchaVerified() {
  return _pzVerified;
}
