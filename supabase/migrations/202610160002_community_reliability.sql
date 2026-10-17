-- Additive fixes: preserve existing users, content, messages and RLS isolation.
begin;

drop policy comment_insert on public.community_comments;
create policy comment_insert on public.community_comments for insert to authenticated
with check (author_id=auth.uid() and community_private.answer_visible(answer_id)
  and (parent_id is null or exists (
    select 1 from public.community_comments p
    where p.id=community_comments.parent_id and p.answer_id=community_comments.answer_id
  )));

-- Blocking still hides content, but cannot prevent its author from withdrawing it.
create function public.delete_own_community_content(content_table text, content_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare removed uuid;
begin
  if auth.uid() is null then raise exception '请登录' using errcode='42501'; end if;
  case content_table
    when 'community_questions' then
      delete from public.community_questions where id=content_id and author_id=auth.uid() returning id into removed;
    when 'community_answers' then
      delete from public.community_answers where id=content_id and author_id=auth.uid() returning id into removed;
    when 'community_comments' then
      delete from public.community_comments where id=content_id and author_id=auth.uid() returning id into removed;
    else raise exception '无效内容类型' using errcode='23514';
  end case;
  return removed is not null;
end $$;

-- A pending local message is permanently owned by its original sender. If the
-- client changes accounts while awaiting upload/network, this transaction fails.
create function public.send_chat_message(cid uuid, token uuid, message_body text,
  image text, expected_sender uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare lo uuid; hi uuid; result uuid; previous public.chat_messages;
begin
  if auth.uid() is null or auth.uid() is distinct from expected_sender then
    raise exception '登录账号已改变，请重新打开聊天' using errcode='42501';
  end if;
  select user_low,user_high into lo,hi from public.conversations where id=cid;
  if not found then raise exception '会话不可用' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(lo::text || hi::text,0));
  if not community_private.can_chat(cid) then
    raise exception '无权发送消息' using errcode='42501';
  end if;
  insert into public.chat_messages(conversation_id,client_token,body,image_path,kind)
    values(cid,token,btrim(message_body),image,case when image is null then 'text' else 'image' end)
    on conflict(sender_id,client_token) do nothing returning id into result;
  if result is null then
    select * into previous from public.chat_messages
      where sender_id=auth.uid() and client_token=token;
    if previous.conversation_id is distinct from cid
      or previous.body is distinct from btrim(message_body)
      or previous.image_path is distinct from image then
      raise exception '重复发送标识对应的内容已改变' using errcode='23514';
    end if;
    result:=previous.id;
  end if;
  return result;
end $$;

-- All supported client sends use the transaction above, including retry.
revoke insert(id,conversation_id,client_token,kind,body,image_path)
  on public.chat_messages from authenticated;
revoke all on function public.delete_own_community_content(text,uuid),
  public.send_chat_message(uuid,uuid,text,text,uuid) from public,anon;
grant execute on function public.delete_own_community_content(text,uuid),
  public.send_chat_message(uuid,uuid,text,text,uuid) to authenticated;

commit;
