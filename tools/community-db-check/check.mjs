import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'node:fs';
import assert from 'node:assert/strict';

// Executes actual PostgreSQL SQL and RLS in PGlite; Supabase Auth/Storage
// infrastructure is represented by the minimal schemas below, not by mocks
// of application tables or access policies.
const db = new PGlite();
await db.exec(`
  create role anon; create role authenticated;
  create schema auth; create schema storage;
  create table auth.users(id uuid primary key,raw_user_meta_data jsonb);
  create function auth.uid() returns uuid language sql stable as
    $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  grant usage on schema auth,storage to authenticated;
  grant execute on function auth.uid() to authenticated;
  create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
  create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner_id text);
  alter table storage.objects enable row level security;
  grant select,insert,delete on storage.objects to authenticated;
  create function storage.foldername(text) returns text[] language sql immutable as
    $$ select string_to_array(regexp_replace($1,'/[^/]+$',''),'/') $$;
  grant execute on function storage.foldername(text) to authenticated;
`);
const migrations = new URL('../../supabase/migrations/', import.meta.url);
const repaired='40000000-0000-4000-8000-000000000004';
const customized='50000000-0000-4000-8000-000000000005';
for (const name of readdirSync(migrations).filter(name => name.endsWith('.sql')).sort()) {
  if (name === '202610170001_registration_nickname.sql') {
    await db.query("insert into auth.users(id,raw_user_meta_data) values($1,$3),($2,$3)",
      [repaired,customized,JSON.stringify({nickname:'yk'})]);
    await db.query("update public.profiles set nickname='已修改昵称' where id=$1",[customized]);
  }
  await db.exec(readFileSync(new URL(name, migrations), 'utf8'));
}
const A='10000000-0000-4000-8000-000000000001', B='20000000-0000-4000-8000-000000000002', C='30000000-0000-4000-8000-000000000003';
for (const id of [A,B,C]) await db.query('insert into auth.users(id) values($1)',[id]);
let checks=0;
async function user(id,sql,args=[]){
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id??'']);
  await db.exec(`set role ${id?'authenticated':'anon'}`);
  return db.query(sql,args);
}
function ok(condition,label){assert.ok(condition,label);checks++;console.log(`PASS ${label}`);}
ok((await user(A,'select nickname from public.profiles where id=$1',[repaired])).rows[0].nickname==='yk','migration repairs untouched default nickname from registration metadata');
ok((await user(A,'select nickname from public.profiles where id=$1',[customized])).rows[0].nickname==='已修改昵称','nickname repair preserves customized profiles');
await db.exec('reset role');
const registered='60000000-0000-4000-8000-000000000006';
await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[registered,JSON.stringify({nickname:'yk'})]);
ok((await user(A,"select id from public.profiles where nickname ilike '%YK%'")).rows.some(row=>row.id===registered),'registered nickname is searchable before first login, case insensitive');
async function denied(id,sql,args,label){
  let rejected=false;
  try{const res=await user(id,sql,args);rejected=res.affectedRows===0||res.rows.length===0;}
  catch(e){if(!['42501','P0001','23514','23503','23505'].includes(e.code))throw e;rejected=true;}
  ok(rejected,label);
}
const q=(await user(A,"insert into public.community_questions(title,body,client_token) values('极限问题','求解 sin(x)/x',gen_random_uuid()) returning id")).rows[0].id;
const answer=(await user(B,"insert into public.community_answers(question_id,body,client_token) values($1,'用泰勒展开',gen_random_uuid()) returning id",[q])).rows[0].id;
ok((await user(B,'select * from public.community_questions where id=$1',[q])).rows.length===1,'different authenticated user can read question');
await denied(null,'select * from public.community_questions',[],'anonymous cannot read community');
await denied(B,"update public.community_questions set title='forged' where id=$1 returning id",[q],'other user cannot edit question');
await denied(B,'delete from public.community_questions where id=$1 returning id',[q],'other user cannot delete question');
await denied(B,'select public.accept_community_answer($1,$2)',[q,answer],'non-author cannot accept answer');
await denied(A,'update public.community_questions set accepted_answer_id=$1 where id=$2 returning id',[answer,q],'client cannot bypass acceptance RPC');
await denied(A,'update public.community_questions set author_id=$1 where id=$2 returning id',[B,q],'client cannot change author');
await user(A,'select public.accept_community_answer($1,$2)',[q,answer]);
ok((await user(A,'select accepted_answer_id from public.community_questions where id=$1',[q])).rows[0].accepted_answer_id===answer,'author can accept valid answer');
const otherQ=(await user(C,"insert into public.community_questions(title,body,client_token) values('另一个问题','正文',gen_random_uuid()) returning id")).rows[0].id;
const otherAnswer=(await user(C,"insert into public.community_answers(question_id,body,client_token) values($1,'答案',gen_random_uuid()) returning id",[otherQ])).rows[0].id;
await denied(A,'select public.accept_community_answer($1,$2)',[q,otherAnswer],'cannot accept answer from another question');
await user(B,'insert into public.community_bookmarks(question_id) values($1)',[q]);
ok((await user(A,'select * from public.community_bookmarks')).rows.length===0,'bookmark identities stay private');
const feed=(await user(A,"select public.community_feed('latest','sin',20,0,null,false) data")).rows[0].data;
ok(feed.length===1&&Number(feed[0].bookmark_count)===1,'feed provides search and aggregate counts');
await denied(A,'select public.open_direct_conversation($1)',[B],'non-friends cannot create conversation');
const request=(await user(A,'select public.send_friend_request($1) id',[B])).rows[0].id;
ok((await user(B,'select public.send_friend_request($1) id',[A])).rows[0].id===request,'opposite friend requests share one pending pair');
await denied(C,'select public.respond_friend_request($1,true)',[request],'third user cannot handle request');
await denied(A,'select public.respond_friend_request($1,true)',[request],'sender cannot accept own request');
await user(B,'select public.respond_friend_request($1,true)',[request]);
await user(B,'select public.respond_friend_request($1,true)',[request]);
ok((await user(A,'select * from public.friendships')).rows.length===1,'acceptance creates one canonical friendship');
const cid=(await user(A,'select public.open_direct_conversation($1) id',[B])).rows[0].id;
ok((await user(B,'select public.open_direct_conversation($1) id',[A])).rows[0].id===cid,'both friends reuse one conversation');
await denied(C,'select * from public.conversations where id=$1',[cid],'third user cannot see conversation');
await denied(C,'insert into public.conversation_members(conversation_id,user_id) values($1,$2) returning user_id',[cid,C],'third user cannot add self to conversation');
const token='99999999-0000-4000-8000-000000000001';
const msg=(await user(A,"select public.send_chat_message($1,$2,'你好',null,$3) id",[cid,token,A])).rows[0].id;
ok((await user(A,"select public.send_chat_message($1,$2,'你好',null,$3) id",[cid,token,A])).rows[0].id===msg,'RPC retry returns the same message');
await denied(A,"select public.send_chat_message($1,$2,'changed',null,$3)",[cid,token,A],'same message token cannot silently replace its body');
await denied(B,"select public.send_chat_message($1,gen_random_uuid(),'old outbox',null,$2)",[cid,A],'account switch cannot send original owner outbox');
await denied(C,"select public.send_chat_message($1,gen_random_uuid(),'intrusion',null,$2)",[cid,C],'third user cannot send through message RPC');
ok((await user(B,'select * from public.chat_messages where conversation_id=$1',[cid])).rows.length===1,'recipient reads persisted message');
await denied(C,'select * from public.chat_messages where conversation_id=$1',[cid],'third user cannot read messages');
await denied(C,"insert into public.chat_messages(conversation_id,client_token,body) values($1,gen_random_uuid(),'入侵') returning id",[cid],'third user cannot send messages');
await denied(B,"insert into public.chat_messages(conversation_id,sender_id,client_token,body) values($1,$2,gen_random_uuid(),'冒充') returning id",[cid,A],'sender identity cannot be spoofed');
await denied(A,"insert into public.chat_messages(conversation_id,client_token,body) values($1,$2,'你好') returning id",[cid,token],'duplicate client token cannot duplicate message');
let inbox=(await user(B,'select public.conversation_inbox() data')).rows[0].data;
ok(Number(inbox[0].unread)===1&&inbox[0].latest.body==='你好','inbox returns latest message and real unread count');
await denied(C,'select public.mark_conversation_read($1,$2)',[cid,msg],'third user cannot mark conversation read');
await user(B,'select public.mark_conversation_read($1,$2)',[cid,msg]);
inbox=(await user(B,'select public.conversation_inbox() data')).rows[0].data;
ok(Number(inbox[0].unread)===0,'read marker clears unread messages');
const image=`${cid}/${A}/photo.png`;
await user(A,'insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3)',['chat-images',image,A]);
ok((await user(B,'select * from storage.objects where name=$1',[image])).rows.length===1,'recipient may access private chat attachment');
await denied(C,'select * from storage.objects where name=$1',[image],'third user cannot access private attachment');
await denied(B,'insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3) returning id',['chat-images',`${cid}/${A}/forged.png`,B],'cannot upload into another sender path');
await denied(A,'insert into public.saved_community_knowledge(question_id,answer_id) values($1,$2) returning id',[q,otherAnswer],'saved answer must belong to referenced question');
await user(A,'insert into public.saved_community_knowledge(question_id,answer_id) values($1,$2)',[q,answer]);
await denied(B,'select * from public.saved_community_knowledge',[],'personal saved references remain private');
const comment=(await user(A,"insert into public.community_comments(answer_id,body,client_token) values($1,'谢谢',gen_random_uuid()) returning id",[answer])).rows[0].id;
const reply=(await user(B,"insert into public.community_comments(answer_id,parent_id,body,client_token) values($1,$2,'不客气',gen_random_uuid()) returning id",[answer,comment])).rows[0].id;
ok((await user(A,'select parent_id from public.community_comments where id=$1',[reply])).rows[0].parent_id===comment,'another user can reply to a visible comment');
await denied(B,"insert into public.community_comments(answer_id,parent_id,body,client_token) values($1,$2,'wrong parent',gen_random_uuid()) returning id",[otherAnswer,comment],'comment parent must belong to same answer');
await user(A,"update public.profiles set nickname='甲同学' where id=$1",[A]);
await user(B,'select public.block_user($1)',[A]);
ok((await user(B,'select blocked_nickname from public.user_blocks')).rows[0].blocked_nickname==='甲同学','blocked user keeps a readable nickname');
await denied(B,'select * from public.community_questions where id=$1',[q],'blocked question author is hidden');
await denied(A,'select * from public.profiles where id=$1',[B],'blocking is mutual for profile visibility');
await denied(A,'select * from public.chat_messages where conversation_id=$1',[cid],'blocking revokes access to chat history');
await denied(A,"insert into public.chat_messages(conversation_id,client_token,body) values($1,gen_random_uuid(),'blocked') returning id",[cid],'blocking prevents further messages');
await denied(A,'select * from storage.objects where name=$1',[image],'blocking revokes private storage reads');
ok((await user(B,'select * from public.friendships')).rows.length===0,'blocking removes friendship atomically');
await denied(A,'select public.send_friend_request($1)',[B],'blocked pair cannot reapply');
await denied(A,'select * from public.user_blocks',[],'other users cannot read block identities');
await denied(A,"select public.send_chat_message($1,gen_random_uuid(),'blocked',null,$2)",[cid,A],'blocking also revokes transaction message sends');
ok((await user(A,"select public.delete_own_community_content('community_answers',$1) removed",[answer])).rows[0].removed===false,'delete RPC cannot remove another author content');
ok((await user(B,"select public.delete_own_community_content('community_comments',$1) removed",[reply])).rows[0].removed===true,'blocked author can withdraw own hidden comment');
ok((await user(B,"select public.delete_own_community_content('community_answers',$1) removed",[answer])).rows[0].removed===true,'blocked author can withdraw own hidden answer');
await denied(null,"select public.delete_own_community_content('community_questions',$1)",[q],'anonymous cannot invoke content deletion');
await user(B,'delete from public.user_blocks where blocked_id=$1',[A]);
await denied(A,'select public.open_direct_conversation($1)',[B],'unblocking does not silently recreate friendship');
await db.exec('reset role');
const rls=(await db.query("select tablename,rowsecurity from pg_tables where schemaname='public'")).rows;
ok(rls.length===14&&rls.every(t=>t.rowsecurity),'RLS enabled on all fourteen application tables');
console.log(`PostgreSQL migration + ${checks} security/business checks passed. Supabase-hosted Auth, Storage HTTP and Realtime still require live tests.`);
await db.close();
