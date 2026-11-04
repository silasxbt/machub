(() => {
  const manifest = chrome.runtime.getManifest();
  const versionEl = document.getElementById('version');
  if (versionEl) versionEl.textContent = manifest.version;

  chrome.storage.sync.set({ hasSeenWelcome: true }, () => {});

  const openOptions = () => {
    const url = chrome.runtime.getURL('options.html');
    chrome.tabs ? chrome.tabs.create({ url }) : window.open(url, '_blank', 'noopener');
  };

  document.getElementById('open-options')?.addEventListener('click', openOptions);

  document.getElementById('close-guide')?.addEventListener('click', () => {
    chrome.storage.sync.set({ hasSeenWelcome: true }, () => {
      window.close();
      setTimeout(() => {
        if (!document.hidden) {
          window.location.href = chrome.runtime.getURL('options.html');
        }
      }, 200);
    });
  });
})();
