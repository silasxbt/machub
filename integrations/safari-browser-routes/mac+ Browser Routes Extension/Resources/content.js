// 在ChatGPT页面自动填入搜索词
(function() {
  // 从URL参数获取搜索词
  const urlParams = new URLSearchParams(window.location.search);
  const searchQuery = urlParams.get('q');

  if (!searchQuery) return;

  // 等待页面加载完成
  const waitForElement = (selector, timeout = 10000) => {
    return new Promise((resolve, reject) => {
      const startTime = Date.now();

      const checkElement = () => {
        const element = document.querySelector(selector);
        if (element) {
          resolve(element);
        } else if (Date.now() - startTime > timeout) {
          reject(new Error('Element not found'));
        } else {
          setTimeout(checkElement, 100);
        }
      };

      checkElement();
    });
  };

  // 尝试多个可能的输入框选择器
  const inputSelectors = [
    '#prompt-textarea',
    '[data-id="root"] textarea',
    'textarea[placeholder*="Message"]',
    'textarea[placeholder*="message"]',
    '[contenteditable="true"]',
    'textarea'
  ];

  const findInputElement = async () => {
    for (const selector of inputSelectors) {
      try {
        const element = await waitForElement(selector, 2000);
        if (element) return element;
      } catch (e) {
        continue;
      }
    }
    return null;
  };

  // 自动填入搜索内容
  const autoFillSearch = async () => {
    try {
      const inputElement = await findInputElement();

      if (inputElement) {
        // 设置输入框值
        if (inputElement.tagName === 'TEXTAREA') {
          inputElement.value = searchQuery;
          inputElement.dispatchEvent(new Event('input', { bubbles: true }));
        } else if (inputElement.contentEditable === 'true') {
          inputElement.textContent = searchQuery;
          inputElement.dispatchEvent(new Event('input', { bubbles: true }));
        }

        // 聚焦到输入框
        inputElement.focus();

        // 可选：自动发送消息
        // 寻找发送按钮
        setTimeout(() => {
          const sendButton = document.querySelector('button[data-testid="send-button"], button[aria-label*="Send"], button svg[data-icon="paper-plane"]')?.closest('button');
          if (sendButton && !sendButton.disabled) {
            sendButton.click();
          }
        }, 500);
      }
    } catch (error) {
      console.error('Auto-fill failed:', error);
    }
  };

  // 延迟执行以确保页面完全加载
  setTimeout(autoFillSearch, 1000);

  // 清理URL参数
  if (window.history.replaceState) {
    const cleanUrl = window.location.pathname + window.location.hash;
    window.history.replaceState({}, document.title, cleanUrl);
  }
})();