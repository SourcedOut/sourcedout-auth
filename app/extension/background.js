// ─── background.js ────────────────────────────────────────────────────────────
// The auth callback is handled entirely by auth-callback.js (loaded inside
// auth.html). That script parses the token, saves the session, and closes the
// tab itself. This listener is a safety net: if auth-callback.js fails to
// close the tab, we close it after 5 seconds.

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  const url        = tab.url ?? ''
  const authPageUrl = chrome.runtime.getURL('auth.html')

  if (!url.startsWith(authPageUrl)) return
  if (changeInfo.status !== 'complete') return

  console.log('[SourcedOut] Auth tab detected — auth-callback.js will handle token.')

  setTimeout(() => {
    chrome.tabs.get(tabId, t => {
      if (chrome.runtime.lastError) return
      if (t && t.url?.startsWith(authPageUrl)) {
        chrome.tabs.remove(tabId).catch(() => {})
      }
    })
  }, 5000)
})
