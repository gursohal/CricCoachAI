-- CricCoach AI Database Schema
-- Run this in Supabase SQL editor

-- Users profile (extends Supabase auth.users)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID REFERENCES auth.users PRIMARY KEY,
  height_cm INTEGER,
  experience_level TEXT CHECK (experience_level IN ('beginner', 'intermediate', 'advanced')) DEFAULT 'beginner',
  playing_role TEXT,
  bowling_style TEXT,
  known_issues TEXT[] DEFAULT '{}',
  subscription_tier TEXT DEFAULT 'free' CHECK (subscription_tier IN ('free', 'pro')),
  analyses_this_month INTEGER DEFAULT 0,
  month_reset_date TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Analysis sessions
CREATE TABLE IF NOT EXISTS analysis_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  analysis_type TEXT CHECK (analysis_type IN ('batting', 'bowling')) NOT NULL,
  overall_score INTEGER DEFAULT 0,
  ai_response JSONB,
  phase_scores JSONB,
  duration_seconds DOUBLE PRECISION,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Key frames (images stored in Supabase Storage, references here)
CREATE TABLE IF NOT EXISTS key_frames (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES analysis_sessions(id) ON DELETE CASCADE,
  phase TEXT NOT NULL,
  image_path TEXT,
  pose_data JSONB,
  angle_data JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_sessions_user ON analysis_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_date ON analysis_sessions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_keyframes_session ON key_frames(session_id);

-- Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE analysis_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE key_frames ENABLE ROW LEVEL SECURITY;

-- Policies: Users can only access their own data
CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can view own sessions" ON analysis_sessions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own sessions" ON analysis_sessions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view own key frames" ON key_frames
  FOR SELECT USING (
    session_id IN (
      SELECT id FROM analysis_sessions WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert own key frames" ON key_frames
  FOR INSERT WITH CHECK (
    session_id IN (
      SELECT id FROM analysis_sessions WHERE user_id = auth.uid()
    )
  );

-- Function to create profile on user signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id) VALUES (NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for auto-creating profile
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Function to check and reset monthly analysis count
CREATE OR REPLACE FUNCTION check_analysis_limit(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_tier TEXT;
  v_count INTEGER;
  v_reset_date TIMESTAMPTZ;
BEGIN
  SELECT subscription_tier, analyses_this_month, month_reset_date
  INTO v_tier, v_count, v_reset_date
  FROM profiles WHERE id = p_user_id;
  
  -- Reset monthly count if new month
  IF v_reset_date < date_trunc('month', NOW()) THEN
    UPDATE profiles SET analyses_this_month = 0, month_reset_date = NOW()
    WHERE id = p_user_id;
    v_count := 0;
  END IF;
  
  -- Pro users have unlimited
  IF v_tier = 'pro' THEN RETURN TRUE; END IF;
  
  -- Free users limited to 3/month
  RETURN v_count < 3;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
