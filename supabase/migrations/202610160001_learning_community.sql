-- Additive migration. Apply with Supabase CLI or the project's SQL editor.
begin;
create schema if not exists community_private;
revoke all on schema community_private from public;
grant usage on schema community_private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  public_id text not null unique default ('ZX' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
  nickname text not null default '新同学' check (char_length(btrim(nickname)) between 1 and 40),
  bio text not null default '' check (char_length(bio)<=300),
  avatar_path text,
  background_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (avatar_path is null or avatar_path like id::text || '/%'),
  check (background_path is null or background_path like id::text || '/%')
);
create table public.community_questions (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  body text not null check (char_length(btrim(body)) between 1 and 20000),
  tags text[] not null default '{}' check (cardinality(tags)<=8),
  image_paths text[] not null default '{}' check (cardinality(image_paths)<=6),
  accepted_answer_id uuid,
  client_token uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(author_id,client_token)
);
create table public.community_answers (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.community_questions(id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 30000),
  client_token uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(author_id,client_token), unique(question_id,id)
);
alter table public.community_questions add constraint question_accepted_answer_fk
  foreign key (accepted_answer_id) references public.community_answers(id) on delete set null;
create table public.community_comments (
  id uuid primary key default gen_random_uuid(),
  answer_id uuid not null references public.community_answers(id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  parent_id uuid,
  body text not null check (char_length(btrim(body)) between 1 and 4000),
  client_token uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(author_id,client_token), unique(answer_id,id),
  foreign key(answer_id,parent_id) references public.community_comments(answer_id,id) on delete cascade
);
create table public.community_bookmarks (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  question_id uuid not null references public.community_questions(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(user_id,question_id)
);
create table public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','accepted','rejected','cancelled')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check(sender_id<>recipient_id)
);
create unique index one_pending_friend_pair on public.friend_requests
  (least(sender_id,recipient_id),greatest(sender_id,recipient_id)) where status='pending';
create table public.friendships (
  user_low uuid not null references public.profiles(id) on delete cascade,
  user_high uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(user_low,user_high), check(user_low<user_high)
);
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_low uuid not null references public.profiles(id) on delete cascade,
  user_high uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(user_low,user_high), check(user_low<user_high)
);
create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  last_read_at timestamptz not null default '-infinity',
  primary key(conversation_id,user_id)
);
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  client_token uuid not null,
  kind text not null default 'text' check(kind in ('text','image')),
  body text not null default '', image_path text,
  created_at timestamptz not null default now(),
  unique(sender_id,client_token),
  check ((kind='text' and char_length(btrim(body)) between 1 and 8000 and image_path is null)
    or (kind='image' and image_path is not null and char_length(body)<=8000)),
  check(image_path is null or image_path like conversation_id::text || '/' || sender_id::text || '/%')
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete cascade,
  kind text not null check(kind in ('answer','comment','accepted','friend_request','friend_accepted','message')),
  question_id uuid references public.community_questions(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete cascade,
  request_id uuid references public.friend_requests(id) on delete cascade,
  read_at timestamptz, created_at timestamptz not null default now()
);
create table public.user_blocks (
  blocker_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  -- Captured at block time: blocking hides the other profile, so the list cannot
  -- resolve a nickname afterwards without leaking a blocked identity.
  blocked_nickname text not null default '同学' check(char_length(btrim(blocked_nickname)) between 1 and 40),
  created_at timestamptz not null default now(), primary key(blocker_id,blocked_id), check(blocker_id<>blocked_id)
);
create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  question_id uuid references public.community_questions(id) on delete cascade,
  answer_id uuid references public.community_answers(id) on delete cascade,
  comment_id uuid references public.community_comments(id) on delete cascade,
  reason text not null check(char_length(btrim(reason)) between 1 and 1000),
  created_at timestamptz not null default now(),
  check(num_nonnulls(question_id,answer_id,comment_id)=1)
);
-- Private cloud reference only; no local filenames, source files or personal knowledge body.
create table public.saved_community_knowledge (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  question_id uuid not null references public.community_questions(id) on delete cascade,
  answer_id uuid,
  created_at timestamptz not null default now(),
  foreign key(question_id,answer_id) references public.community_answers(question_id,id) on delete cascade
);
create unique index saved_question_once on public.saved_community_knowledge(user_id,question_id) where answer_id is null;
create unique index saved_answer_once on public.saved_community_knowledge(user_id,answer_id) where answer_id is not null;
create index questions_page on public.community_questions(created_at desc,id desc);
create index questions_author on public.community_questions(author_id,created_at desc);
create index answers_page on public.community_answers(question_id,created_at,id);
create index answers_author on public.community_answers(author_id,created_at desc);
create index comments_page on public.community_comments(answer_id,created_at,id);
create index bookmark_question on public.community_bookmarks(question_id);
create index requests_recipient on public.friend_requests(recipient_id,status,created_at desc);
create index requests_sender on public.friend_requests(sender_id,status);
create index friendship_high on public.friendships(user_high);
create index conversation_high on public.conversations(user_high);
create index members_user on public.conversation_members(user_id,conversation_id);
create index messages_page on public.chat_messages(conversation_id,created_at desc,id desc);
create index notifications_page on public.notifications(recipient_id,created_at desc,id desc);
create index blocks_reverse on public.user_blocks(blocked_id,blocker_id);

create function community_private.blocked(a uuid,b uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.user_blocks where (blocker_id=a and blocked_id=b) or (blocker_id=b and blocked_id=a));
$$;
create function community_private.can_chat(cid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.conversations c
   join public.friendships f using(user_low,user_high)
   where c.id=cid and auth.uid() in (c.user_low,c.user_high)
   and not community_private.blocked(c.user_low,c.user_high));
$$;
create function community_private.question_visible(qid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.community_questions q
   where q.id=qid and not community_private.blocked(auth.uid(),q.author_id));
$$;
create function community_private.answer_visible(aid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.community_answers a where a.id=aid
   and community_private.question_visible(a.question_id) and not community_private.blocked(auth.uid(),a.author_id));
$$;
create function community_private.touch_updated() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at=now(); return new; end $$;
create function community_private.new_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.profiles(id) values(new.id); return new; end $$;
create trigger community_auth_profile after insert on auth.users for each row execute function community_private.new_profile();
insert into public.profiles(id) select id from auth.users on conflict(id) do nothing;

do $$ declare t text; begin
 foreach t in array array['profiles','community_questions','community_answers','community_comments','friend_requests','conversations'] loop
  execute format('create trigger touch_updated before update on public.%I for each row execute function community_private.touch_updated()',t);
 end loop;
 foreach t in array array['profiles','community_questions','community_answers','community_comments','community_bookmarks','friend_requests','friendships','conversations','conversation_members','chat_messages','notifications','user_blocks','content_reports','saved_community_knowledge'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;

create policy profiles_read on public.profiles for select to authenticated using(not community_private.blocked(auth.uid(),id));
create policy profiles_edit on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
grant update(nickname,bio,avatar_path,background_path) on public.profiles to authenticated;
create policy question_read on public.community_questions for select to authenticated using(not community_private.blocked(auth.uid(),author_id));
create policy question_insert on public.community_questions for insert to authenticated with check(author_id=auth.uid() and accepted_answer_id is null
 and not exists(select 1 from unnest(image_paths) p where p not like auth.uid()::text || '/%'));
create policy question_edit on public.community_questions for update to authenticated using(author_id=auth.uid()) with check(author_id=auth.uid()
 and not exists(select 1 from unnest(image_paths) p where p not like auth.uid()::text || '/%'));
create policy question_delete on public.community_questions for delete to authenticated using(author_id=auth.uid());
grant insert(id,title,body,tags,image_paths,client_token), update(title,body,tags,image_paths),delete on public.community_questions to authenticated;
create policy answer_read on public.community_answers for select to authenticated using(community_private.question_visible(question_id) and not community_private.blocked(auth.uid(),author_id));
create policy answer_insert on public.community_answers for insert to authenticated with check(author_id=auth.uid() and community_private.question_visible(question_id));
create policy answer_edit on public.community_answers for update to authenticated using(author_id=auth.uid() and community_private.question_visible(question_id)) with check(author_id=auth.uid());
create policy answer_delete on public.community_answers for delete to authenticated using(author_id=auth.uid());
grant insert(question_id,body,client_token),update(body),delete on public.community_answers to authenticated;
create policy comment_read on public.community_comments for select to authenticated using(community_private.answer_visible(answer_id) and not community_private.blocked(auth.uid(),author_id));
create policy comment_insert on public.community_comments for insert to authenticated with check(author_id=auth.uid() and community_private.answer_visible(answer_id)
 and (parent_id is null or exists(select 1 from public.community_comments p where p.id=parent_id and p.answer_id=community_comments.answer_id)));
create policy comment_delete on public.community_comments for delete to authenticated using(author_id=auth.uid());
grant insert(answer_id,parent_id,body,client_token),delete on public.community_comments to authenticated;
-- Bookmark rows are private; only the safe feed RPC exposes an aggregate count.
create policy bookmarks_read on public.community_bookmarks for select to authenticated using(user_id=auth.uid());
create policy bookmarks_insert on public.community_bookmarks for insert to authenticated with check(user_id=auth.uid() and community_private.question_visible(question_id));
create policy bookmarks_delete on public.community_bookmarks for delete to authenticated using(user_id=auth.uid());
grant insert(question_id),delete on public.community_bookmarks to authenticated;
create policy requests_read on public.friend_requests for select to authenticated using(auth.uid() in(sender_id,recipient_id) and not community_private.blocked(sender_id,recipient_id));
create policy friends_read on public.friendships for select to authenticated using(auth.uid() in(user_low,user_high) and not community_private.blocked(user_low,user_high));
create policy conversations_read on public.conversations for select to authenticated using(community_private.can_chat(id));
create policy members_read on public.conversation_members for select to authenticated using(community_private.can_chat(conversation_id));
create policy messages_read on public.chat_messages for select to authenticated using(community_private.can_chat(conversation_id));
create policy messages_insert on public.chat_messages for insert to authenticated with check(sender_id=auth.uid() and community_private.can_chat(conversation_id));
grant insert(id,conversation_id,client_token,kind,body,image_path) on public.chat_messages to authenticated;
create policy notifications_read on public.notifications for select to authenticated using(recipient_id=auth.uid() and (actor_id is null or not community_private.blocked(recipient_id,actor_id)));
create policy blocks_read on public.user_blocks for select to authenticated using(blocker_id=auth.uid());
create policy blocks_delete on public.user_blocks for delete to authenticated using(blocker_id=auth.uid());
grant delete on public.user_blocks to authenticated;
create policy report_read on public.content_reports for select to authenticated using(reporter_id=auth.uid());
create policy report_insert on public.content_reports for insert to authenticated with check(reporter_id=auth.uid()
 and (question_id is null or community_private.question_visible(question_id))
 and (answer_id is null or community_private.answer_visible(answer_id))
 and (comment_id is null or exists(select 1 from public.community_comments c where c.id=comment_id)));
grant insert(question_id,answer_id,comment_id,reason) on public.content_reports to authenticated;
create policy saved_read on public.saved_community_knowledge for select to authenticated using(user_id=auth.uid());
create policy saved_insert on public.saved_community_knowledge for insert to authenticated with check(user_id=auth.uid() and community_private.question_visible(question_id) and (answer_id is null or community_private.answer_visible(answer_id)));
create policy saved_delete on public.saved_community_knowledge for delete to authenticated using(user_id=auth.uid());
grant insert(question_id,answer_id),delete on public.saved_community_knowledge to authenticated;

create function public.accept_community_answer(qid uuid,aid uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.community_questions where id=qid and author_id=auth.uid() for update;
 if not found then raise exception '只有问题作者可以采纳' using errcode='42501'; end if;
 if aid is not null and not exists(select 1 from public.community_answers where id=aid and question_id=qid and not community_private.blocked(auth.uid(),author_id)) then
  raise exception '答案不属于该问题或不可访问'; end if;
 update public.community_questions set accepted_answer_id=aid where id=qid;
end $$;
create function public.send_friend_request(target uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare rid uuid; lo uuid:=least(auth.uid(),target); hi uuid:=greatest(auth.uid(),target);
begin
 if auth.uid() is null or target=auth.uid() or community_private.blocked(auth.uid(),target) then raise exception '无法申请好友' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(lo::text || hi::text,0));
 if exists(select 1 from public.friendships where user_low=lo and user_high=hi) then raise exception '已经是好友'; end if;
 select id into rid from public.friend_requests where least(sender_id,recipient_id)=lo and greatest(sender_id,recipient_id)=hi and status='pending';
 if rid is null then insert into public.friend_requests(sender_id,recipient_id) values(auth.uid(),target) returning id into rid; end if;
 return rid;
end $$;
create function public.respond_friend_request(rid uuid,accept boolean) returns void
language plpgsql security definer set search_path='' as $$
declare r public.friend_requests; lo uuid; hi uuid;
begin
 select * into r from public.friend_requests where id=rid;
 if not found or r.recipient_id<>auth.uid() or auth.uid() is null then raise exception '无权处理好友申请' using errcode='42501'; end if;
 lo:=least(r.sender_id,r.recipient_id); hi:=greatest(r.sender_id,r.recipient_id);
 perform pg_advisory_xact_lock(hashtextextended(lo::text || hi::text,0));
 select * into r from public.friend_requests where id=rid for update;
 if r.status<>'pending' then return; end if;
 if community_private.blocked(r.sender_id,r.recipient_id) then raise exception '用户已被屏蔽' using errcode='42501'; end if;
 update public.friend_requests set status=case when accept then 'accepted' else 'rejected' end where id=rid;
 if accept then insert into public.friendships(user_low,user_high) values(lo,hi) on conflict do nothing; end if;
end $$;
create function public.remove_friend(target uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception '请登录' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(least(auth.uid(),target)::text || greatest(auth.uid(),target)::text,0));
 delete from public.friendships where user_low=least(auth.uid(),target) and user_high=greatest(auth.uid(),target);
end $$;
create function public.block_user(target uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or target=auth.uid() then raise exception '无法屏蔽此用户'; end if;
 perform pg_advisory_xact_lock(hashtextextended(least(auth.uid(),target)::text || greatest(auth.uid(),target)::text,0));
 insert into public.user_blocks(blocker_id,blocked_id,blocked_nickname)
  values(auth.uid(),target,coalesce((select nickname from public.profiles where id=target),'同学'))
  on conflict do nothing;
 delete from public.friendships where user_low=least(auth.uid(),target) and user_high=greatest(auth.uid(),target);
 update public.friend_requests set status='cancelled' where status='pending' and least(sender_id,recipient_id)=least(auth.uid(),target) and greatest(sender_id,recipient_id)=greatest(auth.uid(),target);
end $$;
create function public.open_direct_conversation(target uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare cid uuid; lo uuid:=least(auth.uid(),target); hi uuid:=greatest(auth.uid(),target);
begin
 if auth.uid() is null then raise exception '请登录' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(lo::text || hi::text,0));
 if community_private.blocked(lo,hi) or not exists(select 1 from public.friendships where user_low=lo and user_high=hi) then raise exception '仅好友可私聊' using errcode='42501'; end if;
 insert into public.conversations(user_low,user_high) values(lo,hi) on conflict(user_low,user_high) do update set updated_at=public.conversations.updated_at returning id into cid;
 insert into public.conversation_members(conversation_id,user_id) values(cid,lo),(cid,hi) on conflict do nothing;
 return cid;
end $$;
create function public.mark_conversation_read(cid uuid,through_message uuid) returns void
language plpgsql security definer set search_path='' as $$
declare stamp timestamptz;
begin
 if not community_private.can_chat(cid) then raise exception '无权访问会话' using errcode='42501'; end if;
 select created_at into stamp from public.chat_messages where id=through_message and conversation_id=cid;
 if stamp is null then return; end if;
 update public.conversation_members set last_read_at=greatest(last_read_at,stamp) where conversation_id=cid and user_id=auth.uid();
 update public.notifications set read_at=now() where recipient_id=auth.uid() and conversation_id=cid and created_at<=stamp;
end $$;
create function public.read_notification(nid uuid) returns void language sql security definer set search_path='' as $$
 update public.notifications set read_at=now() where id=nid and recipient_id=auth.uid();
$$;

create function community_private.notify(recipient uuid,actor uuid,k text,q uuid default null,c uuid default null,r uuid default null) returns void
language plpgsql security definer set search_path='' as $$
begin
 if recipient<>actor and not community_private.blocked(recipient,actor) then
 insert into public.notifications(recipient_id,actor_id,kind,question_id,conversation_id,request_id) values(recipient,actor,k,q,c,r);
 end if;
end $$;
create function community_private.content_notification() returns trigger language plpgsql security definer set search_path='' as $$
declare recipient uuid; q uuid; other uuid;
begin
 if tg_table_name='community_answers' then
  select author_id into recipient from public.community_questions where id=new.question_id;
  perform community_private.notify(recipient,new.author_id,'answer',new.question_id);
 elsif tg_table_name='community_comments' then
  select author_id,question_id into recipient,q from public.community_answers where id=new.answer_id;
  if new.parent_id is not null then select author_id into recipient from public.community_comments where id=new.parent_id; end if;
  perform community_private.notify(recipient,new.author_id,'comment',q);
 elsif tg_table_name='community_questions' then
  if new.accepted_answer_id is distinct from old.accepted_answer_id and new.accepted_answer_id is not null then
   select author_id into recipient from public.community_answers where id=new.accepted_answer_id;
   perform community_private.notify(recipient,new.author_id,'accepted',new.id);
  end if;
 elsif tg_table_name='friend_requests' then
  if tg_op='INSERT' then perform community_private.notify(new.recipient_id,new.sender_id,'friend_request',null,null,new.id);
  elsif new.status='accepted' and old.status='pending' then perform community_private.notify(new.sender_id,new.recipient_id,'friend_accepted',null,null,new.id); end if;
 elsif tg_table_name='chat_messages' then
  select case when user_low=new.sender_id then user_high else user_low end into other from public.conversations where id=new.conversation_id;
  perform community_private.notify(other,new.sender_id,'message',null,new.conversation_id);
  update public.conversations set updated_at=now() where id=new.conversation_id;
 end if;
 return new;
end $$;
create trigger answer_notify after insert on public.community_answers for each row execute function community_private.content_notification();
create trigger comment_notify after insert on public.community_comments for each row execute function community_private.content_notification();
create trigger accepted_notify after update on public.community_questions for each row execute function community_private.content_notification();
create trigger friend_notify after insert or update on public.friend_requests for each row execute function community_private.content_notification();
create trigger message_notify after insert on public.chat_messages for each row execute function community_private.content_notification();

-- SECURITY DEFINER is limited to explicit visible rows, never arbitrary client user IDs.
create function public.community_feed(mode text default 'latest',keyword text default '',page_size int default 20,page_offset int default 0,author uuid default null,only_bookmarks boolean default false)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x.data order by x.rank desc,x.created_at desc,x.id desc),'[]'::jsonb) from (
  select to_jsonb(q) || jsonb_build_object('profile',to_jsonb(p),'answer_count',
   (select count(*) from public.community_answers a where a.question_id=q.id and not community_private.blocked(auth.uid(),a.author_id)),
   'bookmark_count',(select count(*) from public.community_bookmarks b where b.question_id=q.id),
   'bookmarked',exists(select 1 from public.community_bookmarks b where b.question_id=q.id and b.user_id=auth.uid())) data,
   q.id,q.created_at,
   case when mode='recommended' then (select count(*) from public.community_answers a where a.question_id=q.id) else 0 end rank
  from public.community_questions q join public.profiles p on p.id=q.author_id
  where auth.uid() is not null and not community_private.blocked(auth.uid(),q.author_id)
   and (keyword='' or strpos(lower(q.title || ' ' || q.body),lower(keyword))>0)
   and (author is null or q.author_id=author)
   and (mode<>'unanswered' or not exists(select 1 from public.community_answers a where a.question_id=q.id))
   and (not only_bookmarks or exists(select 1 from public.community_bookmarks b where b.question_id=q.id and b.user_id=auth.uid()))
  order by rank desc,q.created_at desc,q.id desc limit least(greatest(page_size,1),50) offset greatest(page_offset,0)
 ) x;
$$;
create function public.community_user_stats(target uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select case when auth.uid() is null or community_private.blocked(auth.uid(),target) then '{}'::jsonb else jsonb_build_object(
 'answers',(select count(*) from public.community_answers a where a.author_id=target and community_private.question_visible(a.question_id)),
 'friends',(select count(*) from public.friendships f where target in(f.user_low,f.user_high))) end;
$$;
create function public.conversation_inbox() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x.data order by x.stamp desc),'[]'::jsonb) from (
 select to_jsonb(c) || jsonb_build_object('profile',to_jsonb(p),'latest',to_jsonb(m),'unread',
  (select count(*) from public.chat_messages z where z.conversation_id=c.id and z.sender_id<>auth.uid() and z.created_at>cm.last_read_at)) data,
  coalesce(m.created_at,c.created_at) stamp
 from public.conversations c join public.conversation_members cm on cm.conversation_id=c.id and cm.user_id=auth.uid()
 join public.profiles p on p.id=case when c.user_low=auth.uid() then c.user_high else c.user_low end
 left join lateral (select * from public.chat_messages where conversation_id=c.id order by created_at desc,id desc limit 1) m on true
 where community_private.can_chat(c.id)
 ) x;
$$;

-- All buckets are private. Signed URLs are generated only after object RLS succeeds.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('community-images','community-images',false,8388608,array['image/jpeg','image/png','image/webp']),
 ('chat-images','chat-images',false,8388608,array['image/jpeg','image/png','image/webp']),
 ('profile-images','profile-images',false,8388608,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy community_image_insert on storage.objects for insert to authenticated with check(bucket_id='community-images' and (storage.foldername(name))[1]=auth.uid()::text);
create policy community_image_read on storage.objects for select to authenticated using(bucket_id='community-images' and
 ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.community_questions q where name=any(q.image_paths))));
create policy community_image_delete on storage.objects for delete to authenticated using(bucket_id='community-images' and owner_id=auth.uid()::text);
create policy profile_image_insert on storage.objects for insert to authenticated with check(bucket_id='profile-images' and (storage.foldername(name))[1]=auth.uid()::text);
create policy profile_image_read on storage.objects for select to authenticated using(bucket_id='profile-images' and exists(select 1 from public.profiles p where p.avatar_path=name or p.background_path=name or p.id::text=(storage.foldername(name))[1]));
create policy profile_image_delete on storage.objects for delete to authenticated using(bucket_id='profile-images' and owner_id=auth.uid()::text);
create policy chat_image_insert on storage.objects for insert to authenticated with check(bucket_id='chat-images' and
 (storage.foldername(name))[2]=auth.uid()::text and exists(select 1 from public.conversations c where c.id::text=(storage.foldername(name))[1] and community_private.can_chat(c.id)));
create policy chat_image_read on storage.objects for select to authenticated using(bucket_id='chat-images' and exists(
 select 1 from public.conversations c where c.id::text=(storage.foldername(name))[1] and community_private.can_chat(c.id)));
create policy chat_image_delete on storage.objects for delete to authenticated using(bucket_id='chat-images' and owner_id=auth.uid()::text);

-- Restrict default EXECUTE grants including trigger helpers.
revoke all on all functions in schema community_private from public,anon,authenticated;
grant execute on function community_private.blocked(uuid,uuid),community_private.can_chat(uuid),community_private.question_visible(uuid),community_private.answer_visible(uuid) to authenticated;
revoke all on function public.accept_community_answer(uuid,uuid),public.send_friend_request(uuid),public.respond_friend_request(uuid,boolean),public.remove_friend(uuid),public.block_user(uuid),public.open_direct_conversation(uuid),public.mark_conversation_read(uuid,uuid),public.read_notification(uuid),public.community_feed(text,text,int,int,uuid,boolean),public.community_user_stats(uuid),public.conversation_inbox() from public,anon;
grant execute on function public.accept_community_answer(uuid,uuid),public.send_friend_request(uuid),public.respond_friend_request(uuid,boolean),public.remove_friend(uuid),public.block_user(uuid),public.open_direct_conversation(uuid),public.mark_conversation_read(uuid,uuid),public.read_notification(uuid),public.community_feed(text,text,int,int,uuid,boolean),public.community_user_stats(uuid),public.conversation_inbox() to authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  alter publication supabase_realtime add table public.chat_messages,public.notifications,public.friend_requests;
 end if;
end $$;
commit;
