// Supabase Edge Function: POST /api/analyze
// Receives key frames + pose data + scores, calls Claude Vision, returns coaching feedback

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SYSTEM_PROMPT = `You are CricCoach AI, an expert cricket batting and bowling coach with 30 years of experience coaching players from amateur to international level. You analyze technique from video frames and pose data.

You are given:
1. Key frame images from different phases of a batting shot or bowling delivery
2. Measured pose landmark positions for each frame
3. Calculated joint angles at each phase
4. Rule-based scores for each biomechanical checkpoint

Your job is to:
1. Analyze the technique shown in the images and data
2. Identify the TOP 3 most impactful issues to fix (ranked by how much improvement they'd cause)
3. For each issue, provide:
   - A clear, specific description of what's wrong (reference the actual measurements)
   - WHY it matters (how it affects batting/bowling performance)
   - A specific drill to fix it (name the drill, explain how to do it, how many reps)
   - What "fixed" looks like (specific measurable target)
4. Provide 1-2 things the player is doing WELL (positive reinforcement)
5. If this is not their first session, comment on progress from previous sessions

IMPORTANT RULES:
- Be specific. Don't say "your head moves." Say "your head moves 4.2 inches to the off-side at contact — ideal is under 1 inch."
- Use measurements from the data provided. Reference actual angles and positions.
- Be encouraging but honest. Amateur cricketers want real feedback, not generic praise.
- Keep language simple. Avoid jargon unless you immediately explain it.
- Each drill must be doable at home or in a net session with no special equipment.
- If you see signs of a potentially dangerous bowling action (mixed action), flag it prominently as an injury risk.

Respond in this exact JSON format:
{
  "overall_assessment": "One paragraph summary of the technique",
  "overall_score": 72,
  "positives": [
    {
      "title": "Strong base in stance",
      "description": "Your feet are well-positioned at 1.2x shoulder width, giving you a stable platform."
    }
  ],
  "issues": [
    {
      "rank": 1,
      "title": "Head falling to off-side",
      "severity": "critical",
      "description": "At the point of contact, your head has moved 4.2 inches to the off-side...",
      "measured_value": "4.2 inches of lateral head movement",
      "ideal_value": "Less than 1 inch",
      "phase": "contact",
      "why_it_matters": "When your head falls over, your eyes tilt...",
      "drill": {
        "name": "Coin Focus Drill",
        "description": "Place a coin on the crease where you'd make contact...",
        "reps": "20 shadow shots per session",
        "frequency": "Before every net session"
      },
      "target": "Head movement under 1.5 inches within 2 weeks"
    }
  ],
  "progress_note": "Your head stability has improved from 53 to 65 since last session...",
  "next_session_focus": "Focus entirely on head position this week..."
}`;

interface AnalysisPayload {
  analysis_type: string;
  key_frames: {
    phase: string;
    image_base64: string;
    pose_landmarks: Record<string, { x: number; y: number }>;
    measured_angles: Record<string, number>;
  }[];
  rule_scores: Record<string, {
    overall: number;
    checkpoints: { name: string; score: number; measured: string; ideal: string }[];
  }>;
  user_context: {
    height_cm?: number;
    playing_role?: string;
    bowling_style?: string;
    experience_level: string;
    known_issues: string[];
    previous_session_scores?: Record<string, number>;
  };
}

serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "authorization, content-type, x-api-version",
      },
    });
  }

  try {
    // Auth check
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No auth token" }), { status: 401 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    // API version routing
    const apiVersion = req.headers.get("X-API-Version") || "v1";
    if (apiVersion !== "v1") {
      return new Response(
        JSON.stringify({ error: `Unsupported API version: ${apiVersion}. Supported: v1` }),
        { status: 400 }
      );
    }

    // Check rate limit
    const { data: canAnalyze } = await supabase.rpc("check_analysis_limit", {
      p_user_id: user.id,
    });

    if (!canAnalyze) {
      return new Response(
        JSON.stringify({ error: "Analysis limit reached. Upgrade to Pro for unlimited." }),
        { status: 429 }
      );
    }

    // Parse payload
    const payload: AnalysisPayload = await req.json();

    // Build Claude messages
    const userContent: any[] = [];

    // Text description
    let textMessage = `Analyze this ${payload.analysis_type} technique.\n\n`;
    textMessage += `Player info:\n`;
    textMessage += `- Height: ${payload.user_context.height_cm || "unknown"}cm\n`;
    textMessage += `- Role: ${payload.user_context.playing_role || "unknown"}\n`;
    textMessage += `- Experience: ${payload.user_context.experience_level}\n`;
    textMessage += `- Known issues: ${payload.user_context.known_issues?.join(", ") || "none"}\n`;
    
    if (payload.user_context.previous_session_scores) {
      textMessage += `- Previous scores: ${JSON.stringify(payload.user_context.previous_session_scores)}\n`;
    }
    
    textMessage += `\nPhase-by-phase analysis:\n\n`;

    for (const frame of payload.key_frames) {
      const phaseScores = payload.rule_scores[frame.phase];
      textMessage += `Phase: ${frame.phase}\n`;
      textMessage += `Measured angles: ${JSON.stringify(frame.measured_angles)}\n`;
      if (phaseScores) {
        textMessage += `Overall score: ${phaseScores.overall}\n`;
        textMessage += `Checkpoints:\n`;
        for (const cp of phaseScores.checkpoints) {
          textMessage += `  - ${cp.name}: ${cp.score}/100 (measured: ${cp.measured}, ideal: ${cp.ideal})\n`;
        }
      }
      textMessage += `\n`;
    }

    userContent.push({ type: "text", text: textMessage });

    // Add images (Claude format: type "image" with base64 source)
    for (const frame of payload.key_frames) {
      if (frame.image_base64) {
        userContent.push({
          type: "image",
          source: {
            type: "base64",
            media_type: "image/jpeg",
            data: frame.image_base64,
          },
        });
      }
    }

    // Call Anthropic Claude API
    const claudeResponse = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-20250514",
        max_tokens: 2000,
        system: SYSTEM_PROMPT,
        messages: [
          { role: "user", content: userContent },
        ],
        temperature: 0.3,
      }),
    });

    if (!claudeResponse.ok) {
      const errText = await claudeResponse.text();
      console.error("Claude API error:", errText);
      return new Response(
        JSON.stringify({ error: "AI analysis failed", details: errText }),
        { status: 502 }
      );
    }

    const claudeData = await claudeResponse.json();
    
    // Extract text content from Claude's response
    const aiContent = claudeData.content?.find((block: any) => block.type === "text")?.text;

    if (!aiContent) {
      return new Response(
        JSON.stringify({ error: "Empty AI response" }),
        { status: 502 }
      );
    }

    let coachingResponse;
    try {
      // Claude may wrap JSON in markdown code blocks — strip them
      const jsonStr = aiContent.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
      coachingResponse = JSON.parse(jsonStr);
    } catch {
      console.error("Failed to parse AI response:", aiContent);
      return new Response(
        JSON.stringify({ error: "Invalid AI response format" }),
        { status: 502 }
      );
    }

    // Increment analysis count
    await supabase
      .from("profiles")
      .update({ analyses_this_month: supabase.rpc("increment_count") })
      .eq("id", user.id);

    // Store session in database
    const { data: session } = await supabase
      .from("analysis_sessions")
      .insert({
        user_id: user.id,
        analysis_type: payload.analysis_type,
        overall_score: coachingResponse.overall_score || 0,
        ai_response: coachingResponse,
        phase_scores: payload.rule_scores,
      })
      .select()
      .single();

    return new Response(JSON.stringify(coachingResponse), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    console.error("Edge function error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error", message: String(error) }),
      { status: 500 }
    );
  }
});
