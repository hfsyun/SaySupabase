-- =====================================================
-- 补充数据库函数和触发器
-- =====================================================

-- 获取说说列表函数
CREATE OR REPLACE FUNCTION get_says(
    page_offset INTEGER DEFAULT 0,
    page_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    content TEXT,
    author_id UUID,
    username VARCHAR(50),
    avatar TEXT,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.id,
        s.content,
        s.author_id,
        s.username,
        s.avatar,
        s.created_at,
        s.updated_at
    FROM says s
    ORDER BY s.created_at DESC
    OFFSET page_offset
    LIMIT page_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 用户统计函数
CREATE OR REPLACE FUNCTION get_user_stats(user_uuid UUID)
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    SELECT json_build_object(
        'total_says', (SELECT COUNT(*) FROM says WHERE author_id = user_uuid)
    ) INTO result;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 搜索说说函数
CREATE OR REPLACE FUNCTION search_says(
    search_query TEXT,
    page_offset INTEGER DEFAULT 0,
    page_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    content TEXT,
    author_id UUID,
    username VARCHAR(50),
    avatar TEXT,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.id,
        s.content,
        s.author_id,
        s.username,
        s.avatar,
        s.created_at,
        s.updated_at
    FROM says s
    WHERE 
        s.content ILIKE '%' || search_query || '%' OR
        s.username ILIKE '%' || search_query || '%'
    ORDER BY s.created_at DESC
    OFFSET page_offset
    LIMIT page_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 批量获取说说
CREATE OR REPLACE FUNCTION get_says_by_ids(
    ids UUID[]
)
RETURNS SETOF says AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM says
    WHERE id = ANY(ids)
    ORDER BY created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 清理过期会话（可选）
CREATE OR REPLACE FUNCTION clean_expired_sessions()
RETURNS VOID AS $$
BEGIN
    DELETE FROM auth.sessions 
    WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 更新用户头像
CREATE OR REPLACE FUNCTION update_user_avatar(
    user_uuid UUID,
    new_avatar TEXT
)
RETURNS VOID AS $$
BEGIN
    UPDATE user_profiles
    SET avatar = new_avatar,
        updated_at = NOW()
    WHERE id = user_uuid;
    
    UPDATE says
    SET avatar = new_avatar
    WHERE author_id = user_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
