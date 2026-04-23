/*
  # Add email_source column

  1. Changes
    - Add `email_source` TEXT (nullable) to `saved_profiles`
    - Add `email_source` TEXT (nullable) to `outreach_runs`

  2. Purpose
    - Track which step of the enrichment waterfall produced a candidate's email
    - Valid values (not enforced via check constraint to stay flexible):
      - 'claude_pattern'  — pattern-guessed by Claude then verified
      - 'google_search'   — discovered via Google Custom Search then verified
      - 'apollo'          — returned by Apollo (verified)
      - 'fullenrich'      — returned by FullEnrich (last resort)

  3. Notes
    - Columns are nullable to avoid backfilling existing rows
    - Uses IF NOT EXISTS-style DO blocks for idempotency
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'saved_profiles'
      AND column_name = 'email_source'
  ) THEN
    ALTER TABLE saved_profiles ADD COLUMN email_source text;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'outreach_runs'
      AND column_name = 'email_source'
  ) THEN
    ALTER TABLE outreach_runs ADD COLUMN email_source text;
  END IF;
END $$;
