# Fixes for `app/supabase/functions/enrich-and-draft/index.ts`

---

## 🐛 Bugs to Fix

### 1. Confirm Model Name in `generateDraft`

In `generateEmailPatterns` and `resolveEmployer`, the model is correctly set to `claude-haiku-4-5` (cheap, fast).
But in `generateDraft`, the model is `claude-sonnet-4-5`:

```ts
const raw = await callAnthropic(anthropicKey, 'claude-sonnet-4-5', 500, prompt)
```

**This is intentional for draft quality** — Sonnet produces much better outreach emails than Haiku.
Just be aware: Sonnet is ~20× more expensive per call. If cost becomes a concern, swap to `claude-haiku-4-5` here too.
No code change required unless you want to downgrade.

---

### 2. `_incrementCampaignCount` is Called But Never Defined ⚠️ CRITICAL

The function `_incrementCampaignCount(db, campaignId, 'enriched_count')` is called in multiple action handlers but is **not defined anywhere in the file**. This will cause a `ReferenceError` crash the first time any campaign candidate is enriched or drafted.

**Add this function before the `Deno.serve(...)` block:**

```ts
async function _incrementCampaignCount(db: any, campaignId: string, field: string) {
  try {
    await db.rpc('increment_campaign_count', { p_campaign_id: campaignId, p_field: field })
  } catch (e) { console.warn('increment campaign count failed (non-fatal):', e) }
}
```

> Make sure a matching Postgres RPC function `increment_campaign_count(p_campaign_id, p_field)` exists in Supabase. If it doesn't, create a migration for it.

---

### 3. `KNOWN_ACTIONS` Guard — Add a Warning Comment

The `KNOWN_ACTIONS` guard is placed **after** all `if (action === ...)` branches but **before** the `enrich-and-draft` default flow. This works correctly today, but if a new action handler is added later without updating `KNOWN_ACTIONS`, it will silently return a `400` error.

**Add this comment above the guard:**

```ts
// ⚠️ If you add a new action handler above, you MUST also add its name here.
// Forgetting to do so will cause that action to silently return a 400 error.
const KNOWN_ACTIONS = [
  'enrich-and-draft', 'summarize-job', 'bookmark-profile', 'check-saved-profile',
  ...
]
```

---

### 4. Check for Truncated `titleConfidence` Variable

Near the bottom of the `enrich-and-draft` default flow, there may be an incomplete line:

```ts
title = fallback.title; titleCo   // ← looks truncated
```

It should read:

```ts
title = fallback.title; titleConfidence = fallback.confidence
```

**Verify the file is complete and run `supabase functions deploy enrich-and-draft` to confirm there are no build errors.**

---

### 5. FullEnrich Polling Has No Safety Timeout ⚠️ IMPORTANT

`enrichWithLinkedInV2` polls for up to **55 seconds** (3s initial wait + 22 iterations × 5s).
Supabase Edge Functions have a **60s wall-clock timeout** — this leaves almost no margin.

If FullEnrich is slow, the function will time out before returning, leaving the candidate status permanently stuck at `enriching`.

**Fix: cap retries at 18 and wrap in a `Promise.race`:**

```ts
// Change the loop from 22 to 18 iterations
for (let i = 0; i < 18; i++) {  // ~48s max polling

// Wrap the entire enrichWithLinkedInV2 call with a timeout:
const timeoutPromise = new Promise((_, reject) =>
  setTimeout(() => reject(new Error('FullEnrich timeout — 54s exceeded')), 54000)
)
const fe = await Promise.race([enrichWithLinkedInV2(linkedinUrl, keys.fullenrich), timeoutPromise]) as any
```

---

## 💡 Minor Improvements (Low Priority)

### 6. Extract Shared Cache Query Helper

The `check-saved-profile` action and the main `enrich-and-draft` flow build **identical** Supabase cache queries. Extract to a shared helper to avoid drift:

```ts
async function getCachedProfile(db: any, userId: string, linkedinUrl: string) {
  const cacheWindow = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()
  const { data } = await db.from('saved_profiles')
    .select('full_name, work_email, personal_email, title, company, title_verified, email_status, is_bookmarked, enriched_at')
    .eq('user_id', userId)
    .eq('linkedin_url', linkedinUrl)
    .or(`is_bookmarked.eq.true,enriched_at.gte.${cacheWindow}`)
    .limit(1)
    .maybeSingle()
  return data
}
```

---

### 7. `accept_all` Email Verification Should Return `uncertain`, Not `found`

In `verifyEmail`, `accept_all` domains are treated as fully verified:

```ts
if (status === 'valid' || status === 'accept_all') {
  return { verified: true, method: 'myemailverifier', result: status }
}
```

`accept_all` means the domain accepts mail to any address — it does **not** confirm the specific mailbox exists. Consider returning `verified: true` but surfacing this as `emailStatus: 'uncertain'` downstream so the UI can show a softer confidence indicator.
