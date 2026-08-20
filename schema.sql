-- ============================================================
-- MIDAS CRM — Supabase PostgreSQL schema
-- Chạy toàn bộ file này trong Supabase Dashboard > SQL Editor
-- (hoặc supabase db push nếu dùng Supabase CLI)
-- ============================================================

-- ---------- customers ----------
create table if not exists public.customers (
  id            text primary key,
  name          text not null,
  contact       text,
  position      text,
  phone         text,
  email         text,
  website       text,
  industry      text,
  source        text,
  owner         text,
  status        text default 'lead',
  note          text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- ---------- deals ----------
create table if not exists public.deals (
  id               text primary key,
  customer_id      text references public.customers(id) on delete set null,
  name             text not null,
  service          text,
  value            numeric,
  owner            text,
  start_date       date,
  deadline         date,
  next_follow_up   date,
  priority         text default 'medium',
  deal_stage       text default 'lead',
  probability      numeric default 0,
  next_action      text,
  note             text,
  documents        jsonb default '[]'::jsonb   -- mảng {id,title,url,note,addedAt}, giữ nguyên cấu trúc lồng hiện tại
);
create index if not exists deals_customer_id_idx on public.deals(customer_id);

-- ---------- activities (timeline / cập nhật tình trạng / ghi chú deal) ----------
create table if not exists public.activities (
  id            text primary key,
  customer_id   text references public.customers(id) on delete set null,
  deal_id       text references public.deals(id) on delete set null,
  date          timestamptz not null default now(),
  content       text
);
create index if not exists activities_customer_id_idx on public.activities(customer_id);
create index if not exists activities_deal_id_idx on public.activities(deal_id);

-- ---------- next_actions ----------
create table if not exists public.next_actions (
  id            text primary key,
  customer_id   text references public.customers(id) on delete set null,
  deal_id       text references public.deals(id) on delete set null,
  text          text,
  due_date      date,
  done          boolean default false,
  created_at    timestamptz default now()
);
create index if not exists next_actions_customer_id_idx on public.next_actions(customer_id);

-- ---------- meetings ----------
create table if not exists public.meetings (
  id            text primary key,
  customer_id   text references public.customers(id) on delete set null,
  deal_id       text references public.deals(id) on delete set null,
  title         text,
  date          date not null,
  time          text,
  location      text,
  note          text,
  created_at    timestamptz default now()
);
create index if not exists meetings_customer_id_idx on public.meetings(customer_id);
create index if not exists meetings_date_idx on public.meetings(date);

-- ============================================================
-- Row Level Security
-- Phase 1 (hiện tại): CRM chưa có đăng nhập, cả team dùng chung 1 database
-- qua anon/publishable key. Bật RLS + policy cho phép anon đọc/ghi toàn bộ
-- để app tiếp tục hoạt động y như bản localStorage cũ.
-- => Đây là đánh đổi bảo mật tạm thời, chấp nhận được vì:
--    (1) app chỉ dùng nội bộ, không public link
--    (2) anon key KHÔNG phải secret key, không thể bypass RLS
-- Khi triển khai Supabase Auth (Phase 2 trong roadmap), policy dưới đây
-- cần được thay bằng điều kiện theo auth.uid() / role trong bảng profiles.
-- ============================================================
alter table public.customers    enable row level security;
alter table public.deals        enable row level security;
alter table public.activities   enable row level security;
alter table public.next_actions enable row level security;
alter table public.meetings     enable row level security;

drop policy if exists "anon full access" on public.customers;
create policy "anon full access" on public.customers
  for all using (true) with check (true);

drop policy if exists "anon full access" on public.deals;
create policy "anon full access" on public.deals
  for all using (true) with check (true);

drop policy if exists "anon full access" on public.activities;
create policy "anon full access" on public.activities
  for all using (true) with check (true);

drop policy if exists "anon full access" on public.next_actions;
create policy "anon full access" on public.next_actions
  for all using (true) with check (true);

drop policy if exists "anon full access" on public.meetings;
create policy "anon full access" on public.meetings
  for all using (true) with check (true);

-- ============================================================
-- (Chuẩn bị cho Phase 2 — chưa bật, chỉ tạo sẵn bảng để không phải
-- migrate lại sau này. Không có FK tới auth.users để tránh lỗi nếu
-- Auth chưa được bật trong project.)
-- ============================================================
create table if not exists public.profiles (
  id           uuid primary key,
  name         text,
  email        text,
  role         text default 'staff', -- admin | manager | staff
  created_at   timestamptz default now()
);
alter table public.profiles enable row level security;
drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles
  for select using (auth.uid() = id);

-- ============================================================
-- Realtime (tuỳ chọn, bật khi cần đồng bộ tức thời nhiều thiết bị
-- mà không cần refresh — Phase 4 trong roadmap):
-- alter publication supabase_realtime add table public.customers, public.deals, public.activities, public.next_actions, public.meetings;
-- ============================================================
