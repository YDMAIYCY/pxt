-- Initialize searchable public nicknames even before the first app login.
begin;

create or replace function community_private.new_profile() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  insert into public.profiles(id,nickname)
    values(new.id,coalesce(nullif(left(btrim(new.raw_user_meta_data->>'nickname'),40),''),'新同学'));
  return new;
end $$;

-- Repair untouched defaults only; preserve nicknames explicitly saved by users.
update public.profiles p
set nickname=left(btrim(u.raw_user_meta_data->>'nickname'),40)
from auth.users u
where p.id=u.id and p.nickname='新同学' and p.updated_at=p.created_at
  and nullif(btrim(u.raw_user_meta_data->>'nickname'),'') is not null;

commit;
