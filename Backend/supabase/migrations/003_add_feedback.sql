-- Migration 003: Add user feedback column to analysis_sessions
-- Supports P2-7: User Feedback Mechanism (👍/👎 after AI coaching)

ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS user_feedback BOOLEAN DEFAULT NULL;

-- Index for querying unhelpful sessions (for quality review)
CREATE INDEX IF NOT EXISTS idx_analysis_sessions_feedback 
  ON analysis_sessions (user_feedback) 
  WHERE user_feedback IS NOT NULL;
