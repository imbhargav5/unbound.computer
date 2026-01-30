-- =====================================================
-- NEXTBASE ULTIMATE SEED DATA
-- =====================================================
-- This seed file creates test data for development.
-- Run with: supabase db reset (which applies migrations + seed)
--
-- Contents:
-- 1. Marketing author profiles
-- 2. Marketing tags
-- 3. Marketing blog posts
-- 4. Blog post relationships
-- 5. Marketing changelog
-- 6. Changelog author relationships
-- 7. Test users (triggers create profiles)
-- 8. Update user profiles
-- 9. Admin privileges
-- 10. Marketing feedback boards
-- 11. Marketing feedback threads
-- 12. Feedback comments & reactions
-- =====================================================


-- =====================================================
-- MARKETING AUTHOR PROFILES
-- =====================================================
INSERT INTO "public"."marketing_author_profiles" (
    "id", "slug", "display_name", "bio", "avatar_url",
    "website_url", "twitter_handle", "linkedin_handle", "instagram_handle"
) VALUES
    (
        'a1111111-1111-1111-1111-111111111111',
        'john-smith',
        'John Smith',
        'Senior Technical Writer at NextBase. Passionate about making complex topics accessible to developers of all skill levels. 10+ years of experience in developer documentation and tutorials.',
        'https://api.dicebear.com/7.x/avataaars/svg?seed=john',
        'https://johnsmith.dev',
        'johnsmith_dev',
        'johnsmith',
        NULL
    ),
    (
        'a2222222-2222-2222-2222-222222222222',
        'sarah-johnson',
        'Sarah Johnson',
        'Product Lead at NextBase. Building tools that developers love. Previously at Vercel and Stripe. I write about product development, SaaS growth, and team leadership.',
        'https://api.dicebear.com/7.x/avataaars/svg?seed=sarah',
        'https://sarahjohnson.io',
        'sarahj_product',
        'sarahjohnson',
        'sarah.product'
    ),
    (
        'a3333333-3333-3333-3333-333333333333',
        'mike-chen',
        'Mike Chen',
        'Developer Advocate at NextBase. Full-stack developer turned educator. I create tutorials, speak at conferences, and help developers build amazing products with modern tools.',
        'https://api.dicebear.com/7.x/avataaars/svg?seed=mike',
        'https://mikechen.dev',
        'mikechen_dev',
        'mikechendev',
        'mike.codes'
    )
ON CONFLICT (slug) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    bio = EXCLUDED.bio,
    avatar_url = EXCLUDED.avatar_url;


-- =====================================================
-- MARKETING TAGS
-- =====================================================
INSERT INTO "public"."marketing_tags" (
    "id", "slug", "name", "description"
) VALUES
    ('b1111111-1111-1111-1111-111111111111', 'tutorials', 'Tutorials', 'Step-by-step guides and how-to articles for developers'),
    ('b2222222-2222-2222-2222-222222222222', 'product-updates', 'Product Updates', 'Latest features, improvements, and changes to NextBase'),
    ('b3333333-3333-3333-3333-333333333333', 'engineering', 'Engineering', 'Deep dives into technical architecture and implementation details'),
    ('b4444444-4444-4444-4444-444444444444', 'announcements', 'Announcements', 'Important news and announcements from the NextBase team'),
    ('b5555555-5555-5555-5555-555555555555', 'tips-tricks', 'Tips & Tricks', 'Quick tips and productivity hacks for NextBase users'),
    ('b6666666-6666-6666-6666-666666666666', 'case-studies', 'Case Studies', 'Real-world examples of successful NextBase implementations')
ON CONFLICT (slug) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description;


-- =====================================================
-- MARKETING BLOG POSTS
-- =====================================================
INSERT INTO "public"."marketing_blog_posts" (
    "id", "slug", "title", "summary", "content", "json_content",
    "status", "cover_image", "is_featured", "seo_data"
) VALUES
    (
        'c1111111-1111-1111-1111-111111111111',
        'getting-started-with-nextbase',
        'Getting Started with NextBase: A Complete Guide',
        'Learn how to set up your NextBase project from scratch and deploy your first SaaS application in under 30 minutes.',
        E'# Getting Started with NextBase\n\nWelcome to NextBase! This comprehensive guide will walk you through setting up your first project.\n\n## Prerequisites\n\nBefore you begin, make sure you have:\n- Node.js 18+ installed\n- A Supabase account\n- Basic knowledge of React and TypeScript\n\n## Step 1: Clone the Repository\n\nStart by cloning the NextBase template:\n\n```bash\ngit clone https://github.com/nextbase/starter\ncd starter\n```\n\n## Step 2: Install Dependencies\n\n```bash\npnpm install\n```\n\n## Step 3: Configure Environment\n\nCopy the example environment file and fill in your Supabase credentials:\n\n```bash\ncp .env.example .env.local\n```\n\n## Step 4: Start Development\n\n```bash\npnpm dev\n```\n\nYour application is now running at `http://localhost:3000`!\n\n## Next Steps\n\n- Configure authentication providers\n- Set up your database schema\n- Customize the UI to match your brand\n\nHappy building!',
        '{"type": "doc", "content": [{"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "Getting Started with NextBase"}]}, {"type": "paragraph", "content": [{"type": "text", "text": "Welcome to NextBase! This comprehensive guide will walk you through setting up your first project."}]}]}',
        'published',
        'https://images.unsplash.com/photo-1517694712202-14dd9538aa97?w=1200',
        true,
        '{"title": "Getting Started with NextBase - Complete Setup Guide", "description": "Learn how to set up NextBase and deploy your first SaaS application in under 30 minutes.", "keywords": ["nextbase", "tutorial", "saas", "setup"]}'::jsonb
    ),
    (
        'c2222222-2222-2222-2222-222222222222',
        'best-practices-saas-development',
        'Best Practices for Modern SaaS Development',
        'Discover the proven patterns and practices that successful SaaS companies use to build scalable, maintainable applications.',
        E'# Best Practices for Modern SaaS Development\n\nBuilding a successful SaaS application requires more than just good code. Here are the key practices we recommend.\n\n## 1. Start with Authentication\n\nNever roll your own authentication. Use proven solutions like Supabase Auth or Clerk that handle:\n- Session management\n- OAuth providers\n- Password reset flows\n- Email verification\n\n## 2. Design for Security\n\nFrom day one, structure your database with security in mind:\n- Use user IDs for ownership on all tables\n- Implement Row Level Security (RLS)\n- Plan for data isolation\n\n## 3. Implement Proper Error Handling\n\nUsers should never see raw error messages:\n- Log detailed errors server-side\n- Show friendly messages to users\n- Include error boundaries in React\n\n## 4. Plan Your Billing Strategy\n\nChoose your billing model early:\n- Per-seat pricing\n- Usage-based billing\n- Flat-rate subscriptions\n\n## 5. Monitor Everything\n\nSet up monitoring from the start:\n- Application performance\n- Error tracking\n- User analytics\n\n## Conclusion\n\nFollowing these practices will set you up for long-term success.',
        '{"type": "doc", "content": [{"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "Best Practices for Modern SaaS Development"}]}]}',
        'published',
        'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=1200',
        false,
        '{"title": "SaaS Development Best Practices - NextBase Guide", "description": "Learn the proven patterns successful SaaS companies use to build scalable applications.", "keywords": ["saas", "best practices", "development", "scalability"]}'::jsonb
    ),
    (
        'c3333333-3333-3333-3333-333333333333',
        'introducing-new-dashboard',
        'Introducing Our Redesigned Dashboard Experience',
        'We have completely rebuilt the NextBase dashboard with a focus on speed, clarity, and developer experience.',
        E'# Introducing Our Redesigned Dashboard\n\nWe are excited to announce the launch of our completely redesigned dashboard!\n\n## What is New\n\n### Faster Performance\n\nThe new dashboard loads 3x faster thanks to:\n- Server-side rendering with Next.js App Router\n- Optimized database queries\n- Smart caching strategies\n\n### Improved Navigation\n\nFinding what you need is now easier than ever:\n- Collapsible sidebar with quick actions\n- Command palette (Cmd+K) for power users\n- Breadcrumb navigation throughout\n\n### Dark Mode\n\nFinally! Native dark mode support that:\n- Follows your system preference\n- Can be manually toggled\n- Persists across sessions\n\n### Better Analytics\n\nNew analytics widgets show:\n- User growth over time\n- Revenue metrics\n- Feature usage statistics\n\n## Migration Guide\n\nExisting users will be automatically migrated. No action required!\n\n## Feedback\n\nWe would love to hear your thoughts. Use the feedback button in the dashboard to share your experience.',
        '{"type": "doc", "content": [{"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "Introducing Our Redesigned Dashboard"}]}]}',
        'published',
        'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=1200',
        false,
        '{"title": "New NextBase Dashboard - Faster, Cleaner, Better", "description": "Discover the completely redesigned NextBase dashboard with improved performance and UX.", "keywords": ["dashboard", "product update", "nextbase", "ui"]}'::jsonb
    ),
    (
        'c4444444-4444-4444-4444-444444444444',
        'upcoming-features-roadmap-2024',
        'NextBase Roadmap: Upcoming Features in 2024',
        'A sneak peek at the exciting features we are building for NextBase in 2024, including AI integrations and team collaboration tools.',
        E'# NextBase Roadmap 2024\n\nHere is a preview of what we are working on for the coming year.\n\n## Q1: AI Integrations\n\n- **AI Chat Assistant**: Built-in AI helper for your users\n- **Smart Search**: AI-powered search across your content\n- **Auto-generated Documentation**: Let AI write your docs\n\n## Q2: Team Collaboration\n\n- **Real-time Editing**: Collaborative document editing\n- **Team Projects**: Shared spaces for team collaboration\n- **Activity Feeds**: See what your team is working on\n\n## Q3: Enterprise Features\n\n- **SSO Support**: SAML and OIDC authentication\n- **Audit Logs**: Complete activity tracking\n- **Custom Domains**: White-label your application\n\n## Q4: Developer Experience\n\n- **CLI Tools**: Manage your project from the terminal\n- **VS Code Extension**: Integrated development experience\n- **API Explorer**: Interactive API documentation\n\n## How to Participate\n\nJoin our beta program to get early access to these features!\n\n*Note: This roadmap is subject to change based on user feedback and priorities.*',
        '{"type": "doc", "content": [{"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "NextBase Roadmap 2024"}]}]}',
        'draft',
        'https://images.unsplash.com/photo-1484480974693-6ca0a78fb36b?w=1200',
        false,
        '{"title": "NextBase 2024 Roadmap - Upcoming Features", "description": "Preview the exciting features coming to NextBase in 2024.", "keywords": ["roadmap", "features", "2024", "nextbase"]}'::jsonb
    )
ON CONFLICT (slug) DO UPDATE SET
    title = EXCLUDED.title,
    summary = EXCLUDED.summary,
    content = EXCLUDED.content,
    status = EXCLUDED.status;


-- =====================================================
-- BLOG POST TAG RELATIONSHIPS
-- =====================================================
INSERT INTO "public"."marketing_blog_post_tags_relationship" ("blog_post_id", "tag_id")
SELECT bp.id, t.id
FROM (VALUES
    ('getting-started-with-nextbase', 'tutorials'),
    ('getting-started-with-nextbase', 'announcements'),
    ('best-practices-saas-development', 'engineering'),
    ('best-practices-saas-development', 'tips-tricks'),
    ('introducing-new-dashboard', 'product-updates'),
    ('introducing-new-dashboard', 'announcements'),
    ('upcoming-features-roadmap-2024', 'product-updates'),
    ('upcoming-features-roadmap-2024', 'announcements')
) AS rel(post_slug, tag_slug)
JOIN marketing_blog_posts bp ON bp.slug = rel.post_slug
JOIN marketing_tags t ON t.slug = rel.tag_slug
ON CONFLICT DO NOTHING;


-- =====================================================
-- BLOG AUTHOR POST RELATIONSHIPS
-- =====================================================
INSERT INTO "public"."marketing_blog_author_posts" ("author_id", "post_id")
SELECT a.id, bp.id
FROM (VALUES
    ('john-smith', 'getting-started-with-nextbase'),
    ('sarah-johnson', 'best-practices-saas-development'),
    ('sarah-johnson', 'introducing-new-dashboard'),
    ('mike-chen', 'getting-started-with-nextbase'),
    ('sarah-johnson', 'upcoming-features-roadmap-2024')
) AS rel(author_slug, post_slug)
JOIN marketing_author_profiles a ON a.slug = rel.author_slug
JOIN marketing_blog_posts bp ON bp.slug = rel.post_slug
ON CONFLICT DO NOTHING;


-- =====================================================
-- MARKETING CHANGELOG
-- =====================================================
INSERT INTO "public"."marketing_changelog" (
    "id", "title", "json_content", "cover_image", "status", "created_at", "updated_at"
) VALUES
    (
        'c5555555-5555-5555-5555-555555555555',
        'NextBase v2.0 - Major Platform Release',
        '{
            "type": "doc",
            "content": [
                {"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "NextBase v2.0 - Major Platform Release"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "We are thrilled to announce the release of NextBase v2.0, our biggest update yet! This release brings a completely redesigned architecture, improved performance, and many new features."}]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "New Features"}]},
                {"type": "bulletList", "content": [
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Completely redesigned dashboard with improved UX"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "New user management system"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Enhanced API with better rate limiting"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Improved billing integration with Stripe"}]}]}
                ]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Breaking Changes"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "Please review our migration guide for upgrading from v1.x to v2.0."}]}
            ]
        }'::jsonb,
        'https://images.unsplash.com/photo-1551434678-e076c223a692?w=1200',
        'published',
        '2024-11-01 10:00:00+00',
        '2024-11-01 10:00:00+00'
    ),
    (
        'c6666666-6666-6666-6666-666666666666',
        'Introducing Dark Mode',
        '{
            "type": "doc",
            "content": [
                {"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "Introducing Dark Mode"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "By popular demand, we have added native dark mode support to NextBase! Your eyes will thank you during those late-night coding sessions."}]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Features"}]},
                {"type": "bulletList", "content": [
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Automatic detection based on system preferences"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Manual toggle in user settings"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Persistent preference across sessions"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Carefully designed color palette for accessibility"}]}]}
                ]},
                {"type": "paragraph", "content": [{"type": "text", "text": "Enable dark mode from your account settings or use the toggle in the navigation bar."}]}
            ]
        }'::jsonb,
        'https://images.unsplash.com/photo-1555066931-4365d14bab8c?w=1200',
        'published',
        '2024-10-15 14:30:00+00',
        '2024-10-15 14:30:00+00'
    ),
    (
        'c7777777-7777-7777-7777-777777777777',
        'Performance Improvements - 3x Faster Load Times',
        '{
            "type": "doc",
            "content": [
                {"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "Performance Improvements"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "We have been working hard on optimizing NextBase performance. This update brings significant improvements across the board."}]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "What Changed"}]},
                {"type": "bulletList", "content": [
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Dashboard loads 3x faster with optimized queries"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Reduced bundle size by 40% through code splitting"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Implemented smart caching for frequently accessed data"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Optimized image loading with lazy loading and WebP support"}]}]}
                ]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Metrics"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "Average page load time reduced from 2.4s to 0.8s. Time to interactive improved by 65%."}]}
            ]
        }'::jsonb,
        'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=1200',
        'published',
        '2024-09-20 09:00:00+00',
        '2024-09-20 09:00:00+00'
    ),
    (
        'c8888888-8888-8888-8888-888888888888',
        'New API Endpoints for Developers',
        '{
            "type": "doc",
            "content": [
                {"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "New API Endpoints"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "We have expanded our API with new endpoints to give developers more flexibility when building integrations."}]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "New Endpoints"}]},
                {"type": "bulletList", "content": [
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "GET /api/v2/devices - List all devices"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "POST /api/v2/projects - Create new projects programmatically"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "GET /api/v2/analytics - Access analytics data"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "PATCH /api/v2/settings - Update user settings"}]}]}
                ]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Documentation"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "Full API documentation is available at docs.nextbase.dev/api. We have also added interactive examples using Swagger UI."}]}
            ]
        }'::jsonb,
        'https://images.unsplash.com/photo-1516116216624-53e697fedbea?w=1200',
        'published',
        '2024-08-05 11:00:00+00',
        '2024-08-05 11:00:00+00'
    ),
    (
        'c9999999-9999-9999-9999-999999999999',
        'Security Update - Enhanced Authentication',
        '{
            "type": "doc",
            "content": [
                {"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "Security Update"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "Security is our top priority. This update includes several security enhancements to better protect your data."}]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Security Improvements"}]},
                {"type": "bulletList", "content": [
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Two-factor authentication (2FA) support"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Enhanced session management with automatic expiration"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Improved rate limiting to prevent brute force attacks"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Security audit logging for compliance"}]}]}
                ]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Recommendation"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "We strongly recommend enabling 2FA for all admin accounts. You can enable it from your security settings."}]}
            ]
        }'::jsonb,
        'https://images.unsplash.com/photo-1555949963-ff9fe0c870eb?w=1200',
        'published',
        '2024-07-12 16:00:00+00',
        '2024-07-12 16:00:00+00'
    ),
    (
        'ca999999-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'Coming Soon: Team Collaboration Features',
        '{
            "type": "doc",
            "content": [
                {"type": "heading", "attrs": {"level": 1}, "content": [{"type": "text", "text": "Coming Soon: Team Collaboration"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "We are working on exciting new team collaboration features that will make working together even easier."}]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Planned Features"}]},
                {"type": "bulletList", "content": [
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Real-time collaborative editing"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Team activity feeds and notifications"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Enhanced role-based permissions"}]}]},
                    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Team analytics and insights"}]}]}
                ]},
                {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Beta Access"}]},
                {"type": "paragraph", "content": [{"type": "text", "text": "Sign up for our beta program to get early access to these features. We would love your feedback!"}]}
            ]
        }'::jsonb,
        'https://images.unsplash.com/photo-1522071820081-009f0129c71c?w=1200',
        'draft',
        '2024-11-20 08:00:00+00',
        '2024-11-20 08:00:00+00'
    )
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    json_content = EXCLUDED.json_content,
    status = EXCLUDED.status;


-- =====================================================
-- CHANGELOG AUTHOR RELATIONSHIPS
-- =====================================================
INSERT INTO "public"."marketing_changelog_author_relationship" ("author_id", "changelog_id")
SELECT a.id, cl.id
FROM (VALUES
    ('sarah-johnson', 'c5555555-5555-5555-5555-555555555555'),
    ('mike-chen', 'c6666666-6666-6666-6666-666666666666'),
    ('john-smith', 'c7777777-7777-7777-7777-777777777777'),
    ('mike-chen', 'c8888888-8888-8888-8888-888888888888'),
    ('sarah-johnson', 'c9999999-9999-9999-9999-999999999999'),
    ('sarah-johnson', 'ca999999-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
) AS rel(author_slug, changelog_id)
JOIN marketing_author_profiles a ON a.slug = rel.author_slug
JOIN marketing_changelog cl ON cl.id = rel.changelog_id::uuid
ON CONFLICT DO NOTHING;


-- =====================================================
-- TEST USERS
-- =====================================================
-- Note: Inserting into auth.users triggers:
-- - on_auth_user_created_create_profile (creates user_profiles row)
-- Password for all users: "password123" (bcrypt hashed)

INSERT INTO "auth"."users" (
    "instance_id", "id", "aud", "role", "email", "encrypted_password",
    "email_confirmed_at", "invited_at", "confirmation_token", "confirmation_sent_at",
    "recovery_token", "recovery_sent_at", "email_change_token_new", "email_change",
    "email_change_sent_at", "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data",
    "is_super_admin", "created_at", "updated_at", "phone", "phone_confirmed_at",
    "phone_change", "phone_change_token", "phone_change_sent_at",
    "email_change_token_current", "email_change_confirm_status", "banned_until",
    "reauthentication_token", "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous"
) VALUES
    -- Admin User
    (
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-0000-0000-000000000001',
        'authenticated', 'authenticated',
        'testadmin@usenextbase.com',
        '$2a$10$F/GG/iuE6hgeaosm8U599O5I2ykYU6llUnhGdNGPkxC3LDxxXXBOK',
        '2024-01-01 00:00:00+00', NULL, '', NULL, '', NULL, '', '', NULL,
        '2024-11-01 09:00:00+00',
        '{"provider": "email", "providers": ["email"]}',
        '{"full_name": "Admin User"}',
        NULL, '2024-01-01 00:00:00+00', '2024-11-01 09:00:00+00',
        NULL, NULL, '', '', NULL, '', 0, NULL, '', NULL, false, NULL, false
    ),
    -- Alice Johnson - Regular User
    (
        '00000000-0000-0000-0000-000000000000',
        'aaaaaaaa-1111-1111-1111-111111111111',
        'authenticated', 'authenticated',
        'alice@example.com',
        '$2a$10$F/GG/iuE6hgeaosm8U599O5I2ykYU6llUnhGdNGPkxC3LDxxXXBOK',
        '2024-02-15 10:30:00+00', NULL, '', '2024-02-15 10:25:00+00', '', NULL, '', '', NULL,
        '2024-11-10 14:20:00+00',
        '{"provider": "email", "providers": ["email"]}',
        '{"full_name": "Alice Johnson"}',
        NULL, '2024-02-15 10:25:00+00', '2024-11-10 14:20:00+00',
        NULL, NULL, '', '', NULL, '', 0, NULL, '', NULL, false, NULL, false
    ),
    -- Bob Smith - Regular User
    (
        '00000000-0000-0000-0000-000000000000',
        'bbbbbbbb-2222-2222-2222-222222222222',
        'authenticated', 'authenticated',
        'bob@example.com',
        '$2a$10$F/GG/iuE6hgeaosm8U599O5I2ykYU6llUnhGdNGPkxC3LDxxXXBOK',
        '2024-03-20 08:15:00+00', NULL, '', '2024-03-20 08:10:00+00', '', NULL, '', '', NULL,
        '2024-11-15 16:45:00+00',
        '{"provider": "email", "providers": ["email"]}',
        '{"full_name": "Bob Smith"}',
        NULL, '2024-03-20 08:10:00+00', '2024-11-15 16:45:00+00',
        NULL, NULL, '', '', NULL, '', 0, NULL, '', NULL, false, NULL, false
    ),
    -- Carol Williams - Regular User
    (
        '00000000-0000-0000-0000-000000000000',
        'cccccccc-3333-3333-3333-333333333333',
        'authenticated', 'authenticated',
        'carol@example.com',
        '$2a$10$F/GG/iuE6hgeaosm8U599O5I2ykYU6llUnhGdNGPkxC3LDxxXXBOK',
        '2024-04-10 12:00:00+00', NULL, '', '2024-04-10 11:55:00+00', '', NULL, '', '', NULL,
        '2024-11-20 11:30:00+00',
        '{"provider": "email", "providers": ["email"]}',
        '{"full_name": "Carol Williams"}',
        NULL, '2024-04-10 11:55:00+00', '2024-11-20 11:30:00+00',
        NULL, NULL, '', '', NULL, '', 0, NULL, '', NULL, false, NULL, false
    )
ON CONFLICT (id) DO NOTHING;


-- =====================================================
-- UPDATE USER PROFILES
-- =====================================================
-- Profiles are auto-created by trigger, but we update full_name
UPDATE "public"."user_profiles" SET "full_name" = 'Admin User' WHERE "id" = '00000000-0000-0000-0000-000000000001';
UPDATE "public"."user_profiles" SET "full_name" = 'Alice Johnson' WHERE "id" = 'aaaaaaaa-1111-1111-1111-111111111111';
UPDATE "public"."user_profiles" SET "full_name" = 'Bob Smith' WHERE "id" = 'bbbbbbbb-2222-2222-2222-222222222222';
UPDATE "public"."user_profiles" SET "full_name" = 'Carol Williams' WHERE "id" = 'cccccccc-3333-3333-3333-333333333333';


-- =====================================================
-- GRANT ADMIN PRIVILEGES
-- =====================================================
SELECT make_user_app_admin('00000000-0000-0000-0000-000000000001');


-- =====================================================
-- MARKETING FEEDBACK BOARDS
-- =====================================================
INSERT INTO "public"."marketing_feedback_boards" (
    "id", "slug", "title", "description", "is_active", "created_by", "color", "settings"
) VALUES
    (
        'd1111111-1111-1111-1111-111111111111',
        'feature-requests',
        'Feature Requests',
        'Share your ideas for new features and improvements. Vote on suggestions from other users to help us prioritize.',
        true,
        '00000000-0000-0000-0000-000000000001',
        'blue',
        '{"allow_voting": true, "require_approval": false}'::jsonb
    ),
    (
        'd2222222-2222-2222-2222-222222222222',
        'bug-reports',
        'Bug Reports',
        'Found something broken? Report bugs here and help us improve the platform stability.',
        true,
        '00000000-0000-0000-0000-000000000001',
        'red',
        '{"allow_voting": true, "require_approval": false}'::jsonb
    ),
    (
        'd3333333-3333-3333-3333-333333333333',
        'general-feedback',
        'General Feedback',
        'Share your thoughts, suggestions, or any feedback about your experience with NextBase.',
        true,
        '00000000-0000-0000-0000-000000000001',
        'green',
        '{"allow_voting": true, "require_approval": false}'::jsonb
    ),
    (
        'd4444444-4444-4444-4444-444444444444',
        'ideas-suggestions',
        'Ideas & Suggestions',
        'A space for creative ideas and suggestions that could make NextBase even better.',
        true,
        '00000000-0000-0000-0000-000000000001',
        'purple',
        '{"allow_voting": true, "require_approval": false}'::jsonb
    )
ON CONFLICT (slug) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description;


-- =====================================================
-- MARKETING FEEDBACK THREADS
-- =====================================================
INSERT INTO "public"."marketing_feedback_threads" (
    "id", "title", "content", "user_id", "board_id", "type", "status", "priority",
    "is_publicly_visible", "open_for_public_discussion", "added_to_roadmap"
)
SELECT
    t.thread_id::uuid,
    t.title,
    t.content,
    t.user_id::uuid,
    fb.id as board_id,
    t.thread_type::marketing_feedback_thread_type,
    t.thread_status::marketing_feedback_thread_status,
    t.priority::marketing_feedback_thread_priority,
    t.is_public,
    t.open_discussion,
    t.on_roadmap
FROM (VALUES
    -- Feature Requests Board
    (
        'e1111111-1111-1111-1111-111111111111',
        'Add dark mode support',
        'It would be great to have a native dark mode option in the dashboard. Many developers prefer working in dark mode, especially during late hours. This should include:\n\n- System preference detection\n- Manual toggle option\n- Persistence across sessions',
        'aaaaaaaa-1111-1111-1111-111111111111',
        'feature-requests',
        'feature_request', 'completed', 'high',
        true, true, true
    ),
    (
        'e2222222-2222-2222-2222-222222222222',
        'Export data to CSV',
        'Need the ability to export user data and analytics to CSV format for reporting and analysis purposes. This is essential for:\n\n- Monthly reports\n- Data analysis in external tools\n- Compliance requirements',
        'bbbbbbbb-2222-2222-2222-222222222222',
        'feature-requests',
        'feature_request', 'planned', 'medium',
        true, true, true
    ),
    (
        'e3333333-3333-3333-3333-333333333333',
        'API rate limiting dashboard',
        'Would love to see a dashboard showing API usage and rate limit status. This would help us:\n\n- Monitor API consumption\n- Plan capacity\n- Debug rate limit issues',
        'cccccccc-3333-3333-3333-333333333333',
        'feature-requests',
        'feature_request', 'under_review', 'low',
        true, true, false
    ),
    -- Bug Reports Board
    (
        'e4444444-4444-4444-4444-444444444444',
        'Login redirect issue on Safari',
        'When logging in using Safari on macOS, users are sometimes redirected to a blank page instead of the dashboard. Steps to reproduce:\n\n1. Open Safari 17+\n2. Go to login page\n3. Enter credentials\n4. Click submit\n5. ~20% of the time, lands on blank page',
        'aaaaaaaa-1111-1111-1111-111111111111',
        'bug-reports',
        'bug', 'in_progress', 'high',
        true, true, false
    ),
    (
        'e5555555-5555-5555-5555-555555555555',
        'Notification badge not clearing',
        'The notification badge in the header does not clear after viewing notifications. It stays red with the count even after all notifications have been read.',
        'bbbbbbbb-2222-2222-2222-222222222222',
        'bug-reports',
        'bug', 'open', 'low',
        true, true, false
    ),
    -- General Feedback Board
    (
        'e6666666-6666-6666-6666-666666666666',
        'Loving the new dashboard!',
        'Just wanted to say that the new dashboard redesign is fantastic. The navigation is much more intuitive and the performance improvements are very noticeable. Great work team!',
        'cccccccc-3333-3333-3333-333333333333',
        'general-feedback',
        'general', 'closed', 'low',
        true, true, false
    ),
    (
        'e7777777-7777-7777-7777-777777777777',
        'Documentation could be more detailed',
        'The documentation is helpful but some advanced topics could use more detailed explanations and examples. Specifically:\n\n- Custom authentication flows\n- Database migration strategies\n- Performance optimization tips',
        'aaaaaaaa-1111-1111-1111-111111111111',
        'general-feedback',
        'general', 'under_review', 'medium',
        true, true, false
    ),
    -- Ideas & Suggestions Board
    (
        'e8888888-8888-8888-8888-888888888888',
        'Community showcase page',
        'Would be awesome to have a showcase page featuring projects built with NextBase. This would:\n\n- Inspire new users\n- Provide real-world examples\n- Build community engagement',
        'bbbbbbbb-2222-2222-2222-222222222222',
        'ideas-suggestions',
        'feature_request', 'planned', 'medium',
        true, true, true
    ),
    (
        'e9999999-9999-9999-9999-999999999999',
        'Integrate with Figma for design handoff',
        'Direct integration with Figma would streamline the design-to-development workflow. Features could include:\n\n- Import design tokens\n- Generate component code from designs\n- Sync color palettes',
        'cccccccc-3333-3333-3333-333333333333',
        'ideas-suggestions',
        'feature_request', 'open', 'low',
        true, true, false
    )
) AS t(thread_id, title, content, user_id, board_slug, thread_type, thread_status, priority, is_public, open_discussion, on_roadmap)
JOIN marketing_feedback_boards fb ON fb.slug = t.board_slug
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    content = EXCLUDED.content,
    status = EXCLUDED.status;


-- =====================================================
-- MARKETING FEEDBACK COMMENTS
-- =====================================================
INSERT INTO "public"."marketing_feedback_comments" (
    "id", "user_id", "thread_id", "content"
)
SELECT
    c.comment_id::uuid,
    c.user_id::uuid,
    ft.id as thread_id,
    c.content
FROM (VALUES
    -- Comments on "Add dark mode support"
    (
        'f1111111-1111-1111-1111-111111111111',
        'bbbbbbbb-2222-2222-2222-222222222222',
        'e1111111-1111-1111-1111-111111111111',
        'Yes! This would be amazing. I work late nights and a dark mode would really help reduce eye strain.'
    ),
    (
        'f2222222-2222-2222-2222-222222222222',
        'cccccccc-3333-3333-3333-333333333333',
        'e1111111-1111-1111-1111-111111111111',
        'Fully support this! Would also be great if it could sync with the OS-level dark mode setting.'
    ),
    (
        'f3333333-3333-3333-3333-333333333333',
        '00000000-0000-0000-0000-000000000001',
        'e1111111-1111-1111-1111-111111111111',
        'Great news everyone - dark mode has been implemented and is now live! Check your settings to enable it.'
    ),
    -- Comments on "Export data to CSV"
    (
        'f4444444-4444-4444-4444-444444444444',
        'aaaaaaaa-1111-1111-1111-111111111111',
        'e2222222-2222-2222-2222-222222222222',
        'This would be super helpful for generating monthly reports. Currently I have to manually copy data.'
    ),
    (
        'f5555555-5555-5555-5555-555555555555',
        '00000000-0000-0000-0000-000000000001',
        'e2222222-2222-2222-2222-222222222222',
        'We have added this to our Q1 roadmap. Expect CSV export functionality in the next major release!'
    ),
    -- Comments on Safari bug
    (
        'f6666666-6666-6666-6666-666666666666',
        'cccccccc-3333-3333-3333-333333333333',
        'e4444444-4444-4444-4444-444444444444',
        'I can confirm this issue. Happens to me about 1 in 5 login attempts on Safari 17.2.'
    ),
    (
        'f7777777-7777-7777-7777-777777777777',
        '00000000-0000-0000-0000-000000000001',
        'e4444444-4444-4444-4444-444444444444',
        'Thanks for the detailed report. We have identified the issue - it is related to cookie handling in Safari. A fix is in progress.'
    ),
    -- Comments on documentation feedback
    (
        'f8888888-8888-8888-8888-888888888888',
        'bbbbbbbb-2222-2222-2222-222222222222',
        'e7777777-7777-7777-7777-777777777777',
        'Agree on the custom auth flows - took me a while to figure out how to implement passwordless login.'
    )
) AS c(comment_id, user_id, thread_id, content)
JOIN marketing_feedback_threads ft ON ft.id = c.thread_id::uuid
ON CONFLICT (id) DO UPDATE SET
    content = EXCLUDED.content;


-- =====================================================
-- MARKETING FEEDBACK THREAD REACTIONS
-- =====================================================
INSERT INTO "public"."marketing_feedback_thread_reactions" (
    "id", "thread_id", "user_id", "reaction_type"
) VALUES
    -- Reactions on "Add dark mode support"
    ('11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'e1111111-1111-1111-1111-111111111111', 'bbbbbbbb-2222-2222-2222-222222222222', 'upvote'),
    ('22222222-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'e1111111-1111-1111-1111-111111111111', 'cccccccc-3333-3333-3333-333333333333', 'upvote'),
    ('33333333-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'e1111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'heart'),
    -- Reactions on "Export data to CSV"
    ('44444444-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'e2222222-2222-2222-2222-222222222222', 'aaaaaaaa-1111-1111-1111-111111111111', 'upvote'),
    ('55555555-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'e2222222-2222-2222-2222-222222222222', 'cccccccc-3333-3333-3333-333333333333', 'upvote'),
    -- Reactions on "Community showcase"
    ('66666666-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'e8888888-8888-8888-8888-888888888888', 'aaaaaaaa-1111-1111-1111-111111111111', 'celebrate'),
    ('77777777-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'e8888888-8888-8888-8888-888888888888', 'cccccccc-3333-3333-3333-333333333333', 'like'),
    -- Reactions on "Loving the new dashboard"
    ('88888888-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'e6666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000001', 'heart'),
    ('99999999-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'e6666666-6666-6666-6666-666666666666', 'aaaaaaaa-1111-1111-1111-111111111111', 'like')
ON CONFLICT (id) DO NOTHING;


-- =====================================================
-- MARKETING FEEDBACK COMMENT REACTIONS
-- =====================================================
INSERT INTO "public"."marketing_feedback_comment_reactions" (
    "id", "comment_id", "user_id", "reaction_type"
) VALUES
    ('11111111-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'f3333333-3333-3333-3333-333333333333', 'aaaaaaaa-1111-1111-1111-111111111111', 'celebrate'),
    ('22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'f3333333-3333-3333-3333-333333333333', 'bbbbbbbb-2222-2222-2222-222222222222', 'heart'),
    ('33333333-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'f5555555-5555-5555-5555-555555555555', 'bbbbbbbb-2222-2222-2222-222222222222', 'upvote'),
    ('44444444-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'f7777777-7777-7777-7777-777777777777', 'aaaaaaaa-1111-1111-1111-111111111111', 'like')
ON CONFLICT (id) DO NOTHING;


-- =====================================================
-- SEED COMPLETE
-- =====================================================
-- Summary:
-- - 3 marketing authors
-- - 6 blog tags
-- - 4 blog posts (with relationships)
-- - 6 changelog entries (with author relationships)
-- - 4 test users (1 admin + 3 regular)
-- - 4 feedback boards
-- - 9 feedback threads
-- - 8 feedback comments
-- - 13 reactions
-- =====================================================
