-- =====================================================
-- 数据迁移脚本 
-- =====================================================

-- 注意：此脚本需要在Supabase SQL Editor中执行
-- =====================================================
-- 第一步：创建用户函数
-- =====================================================

-- 创建用户函数（返回用户ID）
DROP FUNCTION IF EXISTS create_migration_user(TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION create_migration_user(
    user_email TEXT,
    user_password TEXT,
    user_username TEXT,
    user_avatar TEXT
) RETURNS UUID AS $$
DECLARE
    new_user_id UUID;
    existing_user_id UUID;
BEGIN
    SELECT id INTO existing_user_id 
    FROM auth.users 
    WHERE email = user_email;
    
    IF existing_user_id IS NOT NULL THEN
        INSERT INTO user_profiles (id, username, avatar)
        VALUES (existing_user_id, user_username, user_avatar)
        ON CONFLICT (id) DO UPDATE SET
            username = EXCLUDED.username,
            avatar = EXCLUDED.avatar;
            
        RETURN existing_user_id;
    END IF;
    
    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        confirmation_token,
        email_change,
        email_change_token_new,
        recovery_token
    ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        uuid_generate_v4(),
        'authenticated',
        'authenticated',
        user_email,
        crypt(user_password, gen_salt('bf')),
        NOW(),
        '{"provider":"email","providers":["email"]}',
        json_build_object('username', user_username),
        NOW(),
        NOW(),
        '',
        '',
        '',
        ''
    ) RETURNING id INTO new_user_id;
    
    INSERT INTO user_profiles (id, username, avatar)
    VALUES (new_user_id, user_username, user_avatar)
    ON CONFLICT (id) DO UPDATE SET
        username = EXCLUDED.username,
        avatar = EXCLUDED.avatar;
    
    RETURN new_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 第二步：执行迁移
-- =====================================================

DO $$
DECLARE
    new_id UUID;
BEGIN
    -- 创建用户：
    new_id := create_migration_user(
        'hfsyun@aliyun.com', --注册邮箱
        'pass11111111', --前端说说的密码
        'hfsyun', --用户名
        'https://i0.hdslb.com/bfs/article/318bbf54f45140411e981ed6ce80867244104643.jpg' --用户头像
    );
    
    RAISE NOTICE '用户创建成功，新ID: %', new_id;
END $$;

-- =====================================================
-- 第三步：插入说说数据
-- =====================================================

INSERT INTO says (content, author_id, username, avatar, created_at, updated_at)
SELECT 
    '<p>欢迎来到说说世界！这是我的第一条说说，记录生活的点滴美好。</p>',
    u.id,
    'hfsyun',
    'https://i0.hdslb.com/bfs/article/318bbf54f45140411e981ed6ce80867244104643.jpg',
    NOW(),
    NOW()
FROM auth.users u
WHERE u.email = 'hfsyun@aliyun.com';

-- =====================================================
-- 第四步：验证迁移结果
-- =====================================================

-- 查看迁移的用户
SELECT 
    u.id,
    u.email,
    p.username,
    p.avatar
FROM auth.users u
JOIN user_profiles p ON u.id = p.id;

-- 查看迁移的说说数量
SELECT COUNT(*) as total_says FROM says;

-- 查看最新的说说
SELECT 
    s.id,
    s.content,
    s.username,
    s.created_at
FROM says s
ORDER BY s.created_at DESC
LIMIT 5;
