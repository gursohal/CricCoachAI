-- Feature flags table (public read, admin write)
-- Polled by iOS app on launch for remote config

CREATE TABLE IF NOT EXISTS feature_flags (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed default values
INSERT INTO feature_flags (key, value, description) VALUES
  ('ai_coaching_enabled', 'true', 'Kill switch for AI coaching feature'),
  ('prompt_version', '"v1"', 'Active prompt version for Claude API'),
  ('free_tier_limit', '3', 'Number of free analyses per month'),
  ('min_app_version', '"1.0.0"', 'Minimum supported app version'),
  ('maintenance_mode', 'false', 'Show maintenance banner and disable analysis')
ON CONFLICT (key) DO NOTHING;

-- RLS: Anyone can read, only service role can write
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read feature flags" ON feature_flags
  FOR SELECT USING (true);

-- No INSERT/UPDATE/DELETE policies for anon — admin only via dashboard/service key
