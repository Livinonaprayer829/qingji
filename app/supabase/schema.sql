-- =========================================================
-- daka 记账 App — Supabase 后端 schema
-- 用法:Supabase 后台 → SQL Editor → 粘贴全部内容 → Run
-- 本脚本幂等,可重复执行(已含 if not exists / drop policy)。
-- =========================================================

-- 提供 gen_random_uuid()(Supabase Postgres 13+ 默认可用,此处保险)
create extension if not exists "pgcrypto";

-- ---------------- 账户表 ----------------
create table if not exists public.accounts (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  name        text        not null,
  type        text        not null default 'cash',   -- cash | bank | card | other
  icon        text        not null default '💰',
  currency    text        not null default 'CNY',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------- 分类表 ----------------
create table if not exists public.categories (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  name        text        not null,
  type        text        not null,                        -- income | expense
  icon        text        not null default '📦',
  color       text,                                        -- 十六进制,如 #FF5722
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------- 交易表 ----------------
create table if not exists public.transactions (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  account_id  uuid,        -- 不建外键:交易可能引用本地内置账户/分类的固定 uuid,而这些内置项不上云
  category_id uuid,        -- 同上,由 App 本地维护引用完整性
  type        text        not null,                        -- income | expense | transfer
  amount      numeric(14,2) not null default 0,
  txn_date    date        not null default current_date,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------- 借入借出(债务)表 ----------------
create table if not exists public.loans (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  type        text        not null,                        -- borrow_in | borrow_out
  person      text        not null,                        -- 对方姓名/备注
  amount      numeric(14,2) not null default 0,
  loan_date   date        not null default current_date,   -- 借入/借出日期
  due_date    date,                                        -- 约定还款日
  repaid      boolean     not null default false,          -- 是否已还清
  repaid_date date,                                        -- 还清日期
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------- 索引 ----------------
create index if not exists idx_accounts_user     on public.accounts(user_id);
create index if not exists idx_categories_user   on public.categories(user_id);
create index if not exists idx_transactions_user on public.transactions(user_id);
create index if not exists idx_transactions_date on public.transactions(user_id, txn_date);
create index if not exists idx_loans_user        on public.loans(user_id);

-- ---------------- 行级安全 RLS(用户隔离核心) ----------------
alter table public.accounts     enable row level security;
alter table public.categories  enable row level security;
alter table public.transactions enable row level security;
alter table public.loans       enable row level security;

drop policy if exists "accounts_owner" on public.accounts;
create policy "accounts_owner" on public.accounts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "categories_owner" on public.categories;
create policy "categories_owner" on public.categories
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "transactions_owner" on public.transactions;
create policy "transactions_owner" on public.transactions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "loans_owner" on public.loans;
create policy "loans_owner" on public.loans
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------- updated_at 自动维护 ----------------
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_accounts_updated on public.accounts;
create trigger trg_accounts_updated before update on public.accounts
  for each row execute function public.set_updated_at();

drop trigger if exists trg_categories_updated on public.categories;
create trigger trg_categories_updated before update on public.categories
  for each row execute function public.set_updated_at();

drop trigger if exists trg_transactions_updated on public.transactions;
create trigger trg_transactions_updated before update on public.transactions
  for each row execute function public.set_updated_at();

drop trigger if exists trg_loans_updated on public.loans;
create trigger trg_loans_updated before update on public.loans
  for each row execute function public.set_updated_at();

-- ---------------- 执行后验证(可选) ----------------
-- select 'accounts', count(*) from public.accounts;
-- select 'categories', count(*) from public.categories;
-- select 'transactions', count(*) from public.transactions;

-- =========================================================
-- 迁移:旧项目若已建立 transactions 表的外键,需移除
-- 原因:内置账户/分类使用固定 uuid、不上云,但交易仍会引用这些固定 id,
--      外键约束会导致新用户同步时报 foreign key violation。
-- =========================================================
do $$
declare
  rec record;
begin
  for rec in
    select constraint_name
    from information_schema.table_constraints
    where table_schema = 'public'
      and table_name   = 'transactions'
      and constraint_type = 'FOREIGN KEY'
  loop
    execute format('alter table public.transactions drop constraint if exists %I', rec.constraint_name);
  end loop;
end $$;
