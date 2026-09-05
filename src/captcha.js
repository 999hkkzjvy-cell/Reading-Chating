let activeCaptcha = null;

const PZ_SHAPE = 'path("M0,6 C0,2 2,0 6,0 L44,0 C48,0 50,2 50,6 L50,18 C50,18 40,15 38,22 C36,29 46,28 50,32 L50,44 C50,48 48,50 44,50 L6,50 C2,50 0,48 0,44 L0,6 Z")';
const INSTRUCTION = '拖动滑块使拼图对齐缺口';

function randomGradient() {
  const h1 = Math.floor(Math.random() * 360);
  const h2 = (h1 + 30 + Math.floor(Math.random() * 60)) % 360;
  const h3 = (h1 + 120 + Math.floor(Math.random() * 60)) % 360;
  return `linear-gradient(135deg, hsl(${h1},55%,60%), hsl(${h2},65%,50%), hsl(${h3},55%,55%))`;
}

export function destroyPuzzleCaptcha() {
  activeCaptcha?.destroy();
  activeCaptcha = null;
}

export function initPuzzleCaptcha() {
  // Also called on routes without a puzzle, to dispose the previous instance.
  destroyPuzzleCaptcha();
  const box = document.querySelector('.puzzle-box');
  const slider = document.querySelector('.puzzle-slider');
  if (!box || !slider) return;

  const handle = slider.querySelector('.pz-handle');
  const piece = box.querySelector('.pz-piece');
  const gap = box.querySelector('.pz-gap');
  const status = box.querySelector('.pz-status');
  const track = slider.querySelector('.pz-track');
  const controller = new AbortController();
  const { signal } = controller;
  let pointerId = null;
  let startX = 0;
  let startLeft = 2;
  let left = 2;
  let gapX = 0;
  let boxWidth = 0;
  let sliderWidth = 0;
  let handleMax = 2;
  let observer;
  const pieceStart = 16;
  const state = {
    box,
    verified: false,
    destroy() {
      controller.abort();
      observer?.disconnect();
      releasePointer();
    },
  };
  activeCaptcha = state;

  function releasePointer() {
    const id = pointerId;
    pointerId = null;
    if (id !== null && handle.hasPointerCapture(id)) handle.releasePointerCapture(id);
  }

  function position(nextLeft, snap = false) {
    left = Math.max(2, Math.min(handleMax, nextLeft));
    let pieceLeft = pieceStart + left - 2;
    if (snap && Math.abs(pieceLeft - gapX) <= 10) {
      pieceLeft = gapX;
      left = 2 + gapX - pieceStart;
    }
    handle.style.left = `${left}px`;
    piece.style.left = `${pieceLeft}px`;
    track.style.width = left === 2 ? '0' : `${left + handle.clientWidth / 2}px`;
    const percent = Math.round((left - 2) / Math.max(1, handleMax - 2) * 100);
    handle.setAttribute('aria-valuenow', String(percent));
    handle.setAttribute('aria-valuetext', `位置 ${percent}%，左右方向键调整，回车确认`);
  }

  function resetPuzzle() {
    releasePointer();
    state.verified = false;
    boxWidth = box.clientWidth;
    sliderWidth = slider.clientWidth;
    handleMax = Math.max(2, sliderWidth - handle.clientWidth - 2);
    // Keep the gap reachable even in narrow containers.
    const maxGap = Math.min(boxWidth - 54, pieceStart + handleMax - 2);
    gapX = Math.max(pieceStart, Math.min(maxGap, Math.floor(boxWidth * (0.35 + Math.random() * 0.3))));
    box.classList.remove('success', 'fail');
    slider.classList.remove('success', 'locked');
    status.textContent = INSTRUCTION;
    handle.setAttribute('aria-disabled', 'false');
    const gradient = randomGradient();
    box.querySelector('.pz-bg').style.background = gradient;
    gap.style.left = `${gapX}px`;
    gap.style.clipPath = PZ_SHAPE;
    piece.style.clipPath = PZ_SHAPE;
    // CSS gradients are not valid SVG fill values. Crop the same CSS background.
    piece.style.backgroundImage = gradient;
    piece.style.backgroundSize = `${boxWidth}px 160px`;
    piece.style.backgroundPosition = `-${gapX}px -55px`;
    position(2);
  }

  function cancelDrag() {
    if (pointerId === null) return;
    releasePointer();
    position(2);
    status.textContent = '拖动已取消，可以重新尝试';
  }

  function verify() {
    if (!box.isConnected || state.verified) return;
    if (Math.abs(pieceStart + left - 2 - gapX) <= 10) {
      position(2 + gapX - pieceStart);
      state.verified = true;
      box.classList.remove('fail');
      box.classList.add('success');
      slider.classList.add('success');
      status.textContent = '✓ 验证通过';
      handle.setAttribute('aria-disabled', 'true');
      handle.setAttribute('aria-valuetext', '验证通过');
      box.dispatchEvent(new Event('captcha-verified', { bubbles: true }));
    } else {
      position(2);
      box.classList.add('fail');
      status.textContent = '还差一点，请再试一次';
      // Keep this puzzle and allow immediate retry; no delayed reset or lockout.
    }
  }

  function movePointer(e) {
    const rect = slider.getBoundingClientRect();
    const scale = rect.width ? slider.offsetWidth / rect.width : 1;
    position(startLeft + (e.clientX - startX) * scale, true);
  }

  handle.addEventListener('pointerdown', e => {
    if (state.verified || pointerId !== null || !e.isPrimary || e.button !== 0) return;
    if (boxWidth !== box.clientWidth || sliderWidth !== slider.clientWidth) resetPuzzle();
    if (boxWidth <= 70 || handleMax <= 2) return;
    e.preventDefault();
    handle.focus({ preventScroll: true });
    handle.setPointerCapture(e.pointerId);
    pointerId = e.pointerId;
    startX = e.clientX;
    startLeft = left;
    box.classList.remove('fail');
    status.textContent = INSTRUCTION;
  }, { signal });
  handle.addEventListener('pointermove', e => {
    if (pointerId !== e.pointerId) return;
    movePointer(e);
  }, { signal });
  handle.addEventListener('pointerup', e => {
    if (pointerId !== e.pointerId) return;
    movePointer(e);
    releasePointer();
    verify();
  }, { signal });
  handle.addEventListener('pointercancel', e => {
    if (pointerId === e.pointerId) cancelDrag();
  }, { signal });
  handle.addEventListener('lostpointercapture', e => {
    if (pointerId === e.pointerId) cancelDrag();
  }, { signal });
  window.addEventListener('blur', cancelDrag, { signal });
  handle.addEventListener('keydown', e => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End', 'Enter', ' '].includes(e.key)) return;
    e.preventDefault();
    if (state.verified || pointerId !== null || boxWidth <= 70) return;
    if (e.key === 'Enter' || e.key === ' ') {
      verify();
      return;
    }
    box.classList.remove('fail');
    status.textContent = '左右方向键调整，回车确认';
    const step = e.shiftKey ? 10 : 2;
    const next = e.key === 'Home' ? 2 : e.key === 'End' ? handleMax : left + (e.key === 'ArrowRight' ? step : -step);
    position(next);
  }, { signal });

  resetPuzzle();
  if (typeof ResizeObserver !== 'undefined') {
    observer = new ResizeObserver(() => {
      if (box.isConnected && (boxWidth !== box.clientWidth || sliderWidth !== slider.clientWidth)) {
        // A completed verification remains valid during responsive layout changes.
        if (!state.verified) resetPuzzle();
      }
    });
    observer.observe(box);
    observer.observe(slider);
  }
}

export function refreshCaptcha() {
  initPuzzleCaptcha();
}

export function isCaptchaVerified() {
  return Boolean(activeCaptcha?.box.isConnected && activeCaptcha.verified);
}
