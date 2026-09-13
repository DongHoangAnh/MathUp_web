-- ==============================================================================
-- MATHUP COMPLETE SUPABASE SCHEMA & INITIALIZATION SCRIPT
-- Chạy toàn bộ script này trong SQL Editor của Supabase mới
-- ==============================================================================

-- 1. BẬT EXTENSION UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 2. TẠO CÁC BẢNG (TABLES)
-- ==============================================================================

-- 2.1 Bảng Hồ Sơ Người Dùng (user_profiles)
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    email text,
    full_name text,
    username text UNIQUE,
    role text DEFAULT 'student',
    grade text,
    avatar_url text,
    created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.2 Bảng Thống Kê Điểm & Thành Tích (user_stats)
CREATE TABLE IF NOT EXISTS public.user_stats (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    total_points integer NOT NULL DEFAULT 0,
    lessons_completed integer NOT NULL DEFAULT 0,
    study_time_minutes integer NOT NULL DEFAULT 0,
    total_matches integer NOT NULL DEFAULT 0,
    total_wins integer NOT NULL DEFAULT 0,
    win_streak integer NOT NULL DEFAULT 0,
    best_win_streak integer NOT NULL DEFAULT 0,
    current_rank integer,
    best_rank integer,
    created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.3 Bảng Huy Hiệu (user_achievements)
CREATE TABLE IF NOT EXISTS public.user_achievements (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    achievement_id text NOT NULL,
    achievement_name text NOT NULL,
    achievement_description text,
    achievement_emoji text DEFAULT '⭐',
    earned_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT user_achievements_unique UNIQUE (user_id, achievement_id)
);

-- 2.4 Bảng Kết Quả Đánh Giá Năng Lực (user_assessment_results)
CREATE TABLE IF NOT EXISTS public.user_assessment_results (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL UNIQUE,
    score integer,
    total_questions integer,
    correct_answers integer,
    knowledge_tiles jsonb,
    learning_path jsonb,
    summary text,
    strengths jsonb,
    weaknesses jsonb,
    response_logs jsonb,
    assessed_at timestamp with time zone DEFAULT timezone('utc'::text, now()),
    created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.5 Bảng Lộ Trình Học Cá Nhân Hoá (learning_paths)
CREATE TABLE IF NOT EXISTS public.learning_paths (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL,
    title text,
    subject text NOT NULL DEFAULT 'math',
    estimated_duration text,
    topics jsonb NOT NULL DEFAULT '[]'::jsonb,
    status text DEFAULT 'active',
    priority text DEFAULT 'foundational-gaps',
    progress integer DEFAULT 0,
    created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.6 Bảng Đăng Ký Gói / Thanh Toán (subscriptions)
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL,
    plan_type text NOT NULL,
    status text NOT NULL DEFAULT 'active',
    start_date timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
    end_date timestamp with time zone,
    price integer DEFAULT 0,
    payment_method text,
    transaction_id text,
    auto_renew boolean DEFAULT false,
    created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.7 Bảng Trận Đấu GameShow (game_matches)
CREATE TABLE IF NOT EXISTS public.game_matches (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    room_id text NOT NULL,
    player1_id uuid NOT NULL,
    player2_id uuid NOT NULL,
    player1_display_name text NOT NULL,
    player2_display_name text NOT NULL,
    player1_score integer NOT NULL DEFAULT 0,
    player2_score integer NOT NULL DEFAULT 0,
    player1_correct integer NOT NULL DEFAULT 0,
    player2_correct integer NOT NULL DEFAULT 0,
    player1_total_time_ms integer NOT NULL DEFAULT 0,
    player2_total_time_ms integer NOT NULL DEFAULT 0,
    winner_id uuid,
    questions_count integer NOT NULL DEFAULT 10,
    created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.8 View xem lịch sử trận đấu (game_match_history)
CREATE OR REPLACE VIEW public.game_match_history AS
SELECT * FROM public.game_matches;

-- ==============================================================================
-- 3. INDEXES TỐI ƯU HIỆU NĂNG
-- ==============================================================================
CREATE INDEX IF NOT EXISTS idx_user_profiles_username ON public.user_profiles(username);
CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON public.user_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_stats_points ON public.user_stats(total_points DESC);
CREATE INDEX IF NOT EXISTS idx_game_matches_p1 ON public.game_matches(player1_id);
CREATE INDEX IF NOT EXISTS idx_game_matches_p2 ON public.game_matches(player2_id);
CREATE INDEX IF NOT EXISTS idx_game_matches_created ON public.game_matches(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_learning_paths_user ON public.learning_paths(user_id);

-- ==============================================================================
-- 4. TRIGGER TỰ ĐỘNG TẠO USER PROFILE KHI ĐĂNG KÝ
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.user_profiles (user_id, username, full_name, email, role, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1)),
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'role', 'student'),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (user_id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = COALESCE(user_profiles.full_name, EXCLUDED.full_name),
        updated_at = timezone('utc'::text, now());

    -- Tự động tạo bản ghi user_stats ban đầu
    INSERT INTO public.user_stats (user_id, total_points)
    VALUES (NEW.id, 0)
    ON CONFLICT (user_id) DO NOTHING;

    RETURN NEW;
EXCEPTION WHEN others THEN
    RAISE WARNING 'handle_new_user failed: %', SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ==============================================================================
-- 5. RPC FUNCTIONS CHO BACKEND (GAMESHOW & BẢNG XẾP HẠNG)
-- ==============================================================================

-- 5.1 Cập nhật điểm sau trận đấu GameShow
CREATE OR REPLACE FUNCTION public.upsert_user_stats_gameshow(
    p_user_id uuid,
    p_point_delta integer,
    p_is_winner boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.user_stats (
        user_id,
        total_points,
        total_matches,
        total_wins,
        win_streak,
        best_win_streak
    )
    VALUES (
        p_user_id,
        GREATEST(0, p_point_delta),
        1,
        CASE WHEN p_is_winner THEN 1 ELSE 0 END,
        CASE WHEN p_is_winner THEN 1 ELSE 0 END,
        CASE WHEN p_is_winner THEN 1 ELSE 0 END
    )
    ON CONFLICT (user_id) DO UPDATE SET
        total_points = GREATEST(0, user_stats.total_points + p_point_delta),
        total_matches = user_stats.total_matches + 1,
        total_wins = user_stats.total_wins + (CASE WHEN p_is_winner THEN 1 ELSE 0 END),
        win_streak = CASE WHEN p_is_winner THEN user_stats.win_streak + 1 ELSE 0 END,
        best_win_streak = GREATEST(
            user_stats.best_win_streak,
            CASE WHEN p_is_winner THEN user_stats.win_streak + 1 ELSE 0 END
        ),
        updated_at = timezone('utc'::text, now());
END;
$$;

-- 5.2 Lấy bảng xếp hạng GameShow
CREATE OR REPLACE FUNCTION public.get_gameshow_leaderboard(p_limit integer DEFAULT 20)
RETURNS TABLE (
    user_id uuid,
    display_name text,
    avatar_url text,
    total_points integer,
    total_matches integer,
    total_wins integer,
    win_rate numeric
)
LANGUAGE sql
STABLE
AS $$
    SELECT 
        s.user_id,
        COALESCE(p.full_name, p.username, 'Học sinh') as display_name,
        p.avatar_url,
        s.total_points,
        s.total_matches,
        s.total_wins,
        CASE WHEN s.total_matches > 0 
             THEN ROUND((s.total_wins::numeric / s.total_matches::numeric) * 100, 1) 
             ELSE 0 
        END as win_rate
    FROM public.user_stats s
    LEFT JOIN public.user_profiles p ON p.user_id = s.user_id
    ORDER BY s.total_points DESC, s.total_wins DESC
    LIMIT p_limit;
$$;

-- ==============================================================================
-- 6. PHÂN QUYỀN ROW LEVEL SECURITY (RLS)
-- ==============================================================================
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_assessment_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learning_paths ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_matches ENABLE ROW LEVEL SECURITY;

-- 6.1 Policies cho user_profiles
DROP POLICY IF EXISTS "Allow public read user_profiles" ON public.user_profiles;
CREATE POLICY "Allow public read user_profiles" ON public.user_profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow users insert own profile" ON public.user_profiles;
CREATE POLICY "Allow users insert own profile" ON public.user_profiles FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Allow users update own profile" ON public.user_profiles;
CREATE POLICY "Allow users update own profile" ON public.user_profiles FOR UPDATE USING (auth.uid() = user_id OR auth.uid() IS NULL);

-- 6.2 Policies cho user_stats
DROP POLICY IF EXISTS "Allow public read user_stats" ON public.user_stats;
CREATE POLICY "Allow public read user_stats" ON public.user_stats FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow all for user_stats" ON public.user_stats;
CREATE POLICY "Allow all for user_stats" ON public.user_stats FOR ALL USING (true) WITH CHECK (true);

-- 6.3 Policies cho user_achievements
DROP POLICY IF EXISTS "Allow all user_achievements" ON public.user_achievements;
CREATE POLICY "Allow all user_achievements" ON public.user_achievements FOR ALL USING (true) WITH CHECK (true);

-- 6.4 Policies cho user_assessment_results
DROP POLICY IF EXISTS "Allow all user_assessment_results" ON public.user_assessment_results;
CREATE POLICY "Allow all user_assessment_results" ON public.user_assessment_results FOR ALL USING (true) WITH CHECK (true);

-- 6.5 Policies cho learning_paths
DROP POLICY IF EXISTS "Allow all learning_paths" ON public.learning_paths;
CREATE POLICY "Allow all learning_paths" ON public.learning_paths FOR ALL USING (true) WITH CHECK (true);

-- 6.6 Policies cho subscriptions
DROP POLICY IF EXISTS "Allow all subscriptions" ON public.subscriptions;
CREATE POLICY "Allow all subscriptions" ON public.subscriptions FOR ALL USING (true) WITH CHECK (true);

-- 6.7 Policies cho game_matches
DROP POLICY IF EXISTS "Allow all game_matches" ON public.game_matches;
CREATE POLICY "Allow all game_matches" ON public.game_matches FOR ALL USING (true) WITH CHECK (true);
