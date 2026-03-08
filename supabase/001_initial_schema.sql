-- =====================================================
-- Supabase 数据库迁移脚本
-- =====================================================

-- 启用必要的扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- 1. 用户表 (使用 Supabase Auth，创建扩展表)
-- =====================================================

-- 用户扩展信息表
CREATE TABLE IF NOT EXISTS user_profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    avatar TEXT DEFAULT 'https://api.dicebear.com/7.x/avataaars/svg?seed=default',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 用户名索引
CREATE INDEX IF NOT EXISTS idx_user_profiles_username ON user_profiles(username);

-- 自动创建用户配置的触发器
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_profiles (id, username)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1)));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 删除已存在的触发器（如果有）
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 创建触发器
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =====================================================
-- 2. 说说表 (Say)
-- =====================================================

CREATE TABLE IF NOT EXISTS says (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    content TEXT NOT NULL,
    author_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    username VARCHAR(50) NOT NULL,
    avatar TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 索引优化
CREATE INDEX IF NOT EXISTS idx_says_created_at ON says(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_says_author_id ON says(author_id);

-- 更新时间戳触发器
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_says_updated_at
    BEFORE UPDATE ON says
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- 3. Row Level Security (RLS) 策略
-- =====================================================

-- 启用 RLS
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE says ENABLE ROW LEVEL SECURITY;

-- 用户配置表策略
CREATE POLICY "用户可以查看所有用户配置" ON user_profiles
    FOR SELECT USING (true);

CREATE POLICY "用户只能更新自己的配置" ON user_profiles
    FOR UPDATE USING (auth.uid() = id);

-- 说说表策略
CREATE POLICY "所有人可以查看说说" ON says
    FOR SELECT USING (true);

CREATE POLICY "登录用户可以创建说说" ON says
    FOR INSERT WITH CHECK (auth.uid() = author_id);

CREATE POLICY "作者可以更新自己的说说" ON says
    FOR UPDATE USING (auth.uid() = author_id);

CREATE POLICY "作者可以删除自己的说说" ON says
    FOR DELETE USING (auth.uid() = author_id);

-- =====================================================
-- 4. 存储桶配置 (用于文件上传)
-- =====================================================

-- 创建头像存储桶
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- 删除已存在的存储桶策略（如果有）
DROP POLICY IF EXISTS "所有人可以查看头像" ON storage.objects;
DROP POLICY IF EXISTS "登录用户可以上传头像" ON storage.objects;
DROP POLICY IF EXISTS "用户可以更新自己的头像" ON storage.objects;

-- 存储桶策略
CREATE POLICY "所有人可以查看头像" ON storage.objects
    FOR SELECT USING (bucket_id = 'avatars');

CREATE POLICY "登录用户可以上传头像" ON storage.objects
    FOR INSERT WITH CHECK (bucket_id = 'avatars' AND auth.role() = 'authenticated');

CREATE POLICY "用户可以更新自己的头像" ON storage.objects
    FOR UPDATE USING (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);

-- =====================================================
-- 5. 实时订阅配置
-- =====================================================

-- 为实时功能添加副本标识
ALTER TABLE says REPLICA IDENTITY FULL;

-- =====================================================
-- 6. 视图
-- =====================================================

-- 获取说说列表（包含作者信息）
CREATE OR REPLACE VIEW says_with_author AS
SELECT 
    s.id,
    s.content,
    s.author_id,
    s.created_at,
    s.updated_at,
    COALESCE(s.username, up.username) as username,
    COALESCE(s.avatar, up.avatar) as avatar
FROM says s
LEFT JOIN user_profiles up ON s.author_id = up.id
ORDER BY s.created_at DESC;
