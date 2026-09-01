-- ============================================================================
-- Summer Bottle: Supabase 初期スキーマ (001_init.sql)
--
-- Supabase ダッシュボードの SQL Editor にそのまま貼り付けて実行できる。
-- 再実行しても壊れないように if exists / if not exists を使っている。
--
-- 構成:
--   1. テーブル (bottles / bottle_photos / bottle_objects / bottle_audio)
--      ※ 現行アプリは bottles.payload (jsonb) に Bottle 全体を保存する。
--         子テーブルは仕様書17章どおり定義するが、アプリは書き込まない(将来用)。
--   2. updated_at 自動更新トリガ
--   3. RLS(全テーブル: 自分の行のみ。子テーブルは bottles 経由の EXISTS)
--   4. Storage バケット bottle-media + RLS ポリシー
--      (オブジェクトパスは <user_id>/<bottle_id>/<fileName>)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. テーブル
-- ----------------------------------------------------------------------------

create table if not exists public.bottles (
  id            uuid primary key,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title         text not null default '',
  memory_date   timestamptz not null default now(),
  location_name text,
  latitude      double precision,
  longitude     double precision,
  memory_type   text,
  comment       text,
  companions    jsonb not null default '[]'::jsonb,
  is_favorite   boolean not null default false,
  -- SceneConfig 全体(objects 含む)を JSON で保存
  scene_config  jsonb,
  -- アプリの現行同期実装はここに Bottle 全体をエンコードして保存する(復元の正)
  payload       jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists bottles_user_id_idx    on public.bottles (user_id);
create index if not exists bottles_updated_at_idx on public.bottles (updated_at);

create table if not exists public.bottle_photos (
  id            uuid primary key,
  bottle_id     uuid not null references public.bottles (id) on delete cascade,
  file_name     text not null,
  display_order integer not null default 0,
  analysis      jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists bottle_photos_bottle_id_idx on public.bottle_photos (bottle_id);

create table if not exists public.bottle_objects (
  id          uuid primary key,
  bottle_id   uuid not null references public.bottles (id) on delete cascade,
  object_type text not null,
  position_x  real not null default 0,
  position_y  real not null default 0,
  position_z  real not null default 0,
  rotation_y  real not null default 0,
  scale       real not null default 1,
  photo_id    uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists bottle_objects_bottle_id_idx on public.bottle_objects (bottle_id);

create table if not exists public.bottle_audio (
  bottle_id      uuid primary key references public.bottles (id) on delete cascade,
  file_name      text,
  duration       double precision not null default 0,
  audio_type     text not null default 'preset',
  preset         text,
  contains_voice boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. updated_at 自動更新トリガ
--    クライアントが updated_at を明示的に変更して送ってきた場合はその値を尊重する
--    (アプリは端末側の updatedAt を比較に使うため、勝手に上書きしない)。
-- ----------------------------------------------------------------------------

create or replace function public.handle_updated_at()
returns trigger
language plpgsql
as $$
begin
  if new.updated_at is not distinct from old.updated_at then
    new.updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists set_bottles_updated_at on public.bottles;
create trigger set_bottles_updated_at
  before update on public.bottles
  for each row execute function public.handle_updated_at();

drop trigger if exists set_bottle_photos_updated_at on public.bottle_photos;
create trigger set_bottle_photos_updated_at
  before update on public.bottle_photos
  for each row execute function public.handle_updated_at();

drop trigger if exists set_bottle_objects_updated_at on public.bottle_objects;
create trigger set_bottle_objects_updated_at
  before update on public.bottle_objects
  for each row execute function public.handle_updated_at();

drop trigger if exists set_bottle_audio_updated_at on public.bottle_audio;
create trigger set_bottle_audio_updated_at
  before update on public.bottle_audio
  for each row execute function public.handle_updated_at();

-- ----------------------------------------------------------------------------
-- 3. RLS(Row Level Security)
-- ----------------------------------------------------------------------------

alter table public.bottles        enable row level security;
alter table public.bottle_photos  enable row level security;
alter table public.bottle_objects enable row level security;
alter table public.bottle_audio   enable row level security;

-- bottles: user_id = auth.uid()

drop policy if exists bottles_select_own on public.bottles;
create policy bottles_select_own on public.bottles
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists bottles_insert_own on public.bottles;
create policy bottles_insert_own on public.bottles
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists bottles_update_own on public.bottles;
create policy bottles_update_own on public.bottles
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists bottles_delete_own on public.bottles;
create policy bottles_delete_own on public.bottles
  for delete to authenticated
  using (user_id = auth.uid());

-- bottle_photos: 親 bottle 経由の EXISTS

drop policy if exists bottle_photos_select_own on public.bottle_photos;
create policy bottle_photos_select_own on public.bottle_photos
  for select to authenticated
  using (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

drop policy if exists bottle_photos_insert_own on public.bottle_photos;
create policy bottle_photos_insert_own on public.bottle_photos
  for insert to authenticated
  with check (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

drop policy if exists bottle_photos_update_own on public.bottle_photos;
create policy bottle_photos_update_own on public.bottle_photos
  for update to authenticated
  using (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

drop policy if exists bottle_photos_delete_own on public.bottle_photos;
create policy bottle_photos_delete_own on public.bottle_photos
  for delete to authenticated
  using (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

-- bottle_objects: 親 bottle 経由の EXISTS

drop policy if exists bottle_objects_select_own on public.bottle_objects;
create policy bottle_objects_select_own on public.bottle_objects
  for select to authenticated
  using (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

drop policy if exists bottle_objects_insert_own on public.bottle_objects;
create policy bottle_objects_insert_own on public.bottle_objects
  for insert to authenticated
  with check (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

drop policy if exists bottle_objects_update_own on public.bottle_objects;
create policy bottle_objects_update_own on public.bottle_objects
  for update to authenticated
  using (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

drop policy if exists bottle_objects_delete_own on public.bottle_objects;
create policy bottle_objects_delete_own on public.bottle_objects
  for delete to authenticated
  using (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

-- bottle_audio: 親 bottle 経由の EXISTS

drop policy if exists bottle_audio_select_own on public.bottle_audio;
create policy bottle_audio_select_own on public.bottle_audio
  for select to authenticated
  using (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

drop policy if exists bottle_audio_insert_own on public.bottle_audio;
create policy bottle_audio_insert_own on public.bottle_audio
  for insert to authenticated
  with check (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

drop policy if exists bottle_audio_update_own on public.bottle_audio;
create policy bottle_audio_update_own on public.bottle_audio
  for update to authenticated
  using (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

drop policy if exists bottle_audio_delete_own on public.bottle_audio;
create policy bottle_audio_delete_own on public.bottle_audio
  for delete to authenticated
  using (exists (
    select 1 from public.bottles b
    where b.id = bottle_id and b.user_id = auth.uid()
  ));

-- ----------------------------------------------------------------------------
-- 4. Storage: bottle-media バケット(非公開)+ ポリシー
--    パスは <user_id>/<bottle_id>/<fileName>。先頭フォルダ = auth.uid() のみ許可。
-- ----------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('bottle-media', 'bottle-media', false)
on conflict (id) do nothing;

drop policy if exists bottle_media_select_own on storage.objects;
create policy bottle_media_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'bottle-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists bottle_media_insert_own on storage.objects;
create policy bottle_media_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'bottle-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists bottle_media_update_own on storage.objects;
create policy bottle_media_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'bottle-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'bottle-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists bottle_media_delete_own on storage.objects;
create policy bottle_media_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'bottle-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
