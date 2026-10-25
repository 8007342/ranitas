/* Page-level controls survive Flutter focus and fullscreen keyboard capture. */
(() => {
  'use strict';
  window.addEventListener('keydown', event => {
    if (event.repeat || event.isComposing || event.ctrlKey || event.metaKey || event.altKey) return;
    const target = event.target;
    if (target?.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target?.tagName)) return;
    const key = event.key.toLowerCase();
    if (key === 'escape' || key === 'f') {
      const exit = document.exitFullscreen || document.webkitExitFullscreen;
      if (document.fullscreenElement || document.webkitFullscreenElement) {
        event.preventDefault();
        Promise.resolve(exit?.call(document)).catch(() => {});
      }
    } else if (key === 'r') {
      event.preventDefault();
      // Remove the deterministic preview seed so a reload really is random.
      const url = new URL(window.location.href);
      url.searchParams.delete('seed');
      url.searchParams.delete('duration');
      window.ranitasAudio?.dispose();
      window.location.replace(url.href);
    }
  }, true);
})();
