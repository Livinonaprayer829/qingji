-- 严格 last-write-wins:客户端 updatedAt 与旧值不同时保留客户端值,
-- 这样多端合并时(updatedAt 取较新)才能正确判断。
-- 在 Supabase SQL Editor 里替换原 set_updated_at 函数,幂等可重复执行。

create or replace function public.set_updated_at()
returns trigger as $$
begin
  if new.updated_at is null or new.updated_at = old.updated_at then
    new.updated_at = now();
  end if;
  return new;
end;
$$ language plpgsql security definer;