import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source=await readFile(new URL('../assets/source_lab.js',import.meta.url),'utf8');
const app='https://bechi-flix.137-131-229-110.sslip.io';
async function fixture({origin='https://superflixapi.boats',path='/serie/71225/1/1',status=200,target='https://superflixapi.boats/player/redirect/issued',config={}}={}){
 const timers=[],requests=[],opened=[],notices=[],episodes=[],navigations=[];
 const window={flutter_inappwebview:{callHandler:async(_name,value)=>{notices.push(value);}},
  ALL_EPISODES:{1:[{ID:11,epi_num:1},{ID:22,epi_num:2}]},API_URL_SOURCE:'/player/source',
  fetchBootstrapOptions:(id,done)=>{episodes.push(id);done([{ID:1,type:2},{ID:2,type:1,can_download:true},{ID:3,type:1}]);},
  requirePageTokenClient:()=> 'own-current-session',sfEdgeHeaders:token=>({'X-Page-Token':token}),
  CSRF_TOKEN:'own-csrf',OWNER_CONTEXT_HOST:'bechi.example',openIframe:(...args)=>opened.push(args)};
 window.top=window;
 const context={window,location:{origin,pathname:path,replace:url=>navigations.push(url)},
  document:{querySelectorAll:()=>[]},setInterval:callback=>{timers.push(callback);return timers.length;},clearInterval:()=>{},
  setTimeout,clearTimeout,addEventListener:()=>{},URL,URLSearchParams,AbortSignal,
  sessionStorage:{setItem:()=>{}},fetch:async(url,options)=>{requests.push({url,options});return Response.json({data:{video_url:target}},{status});}};
 await vm.runInNewContext(`(${source})(${JSON.stringify({id:'superflix-telefonistas',season:1,episode:1,origin:app,query:'As Telefonistas',sourceType:'hosted_video',...config})})`,context);
 return {timers,requests,opened,notices,episodes,navigations,context};
}
test('official challenge documents are left entirely to their own code',async()=>{
 const f=await fixture({origin:'https://challenges.cloudflare.com',path:'/turnstile/'});
 assert.equal(f.timers.length,0);assert.equal(f.requests.length,0);assert.equal(f.notices.length,0);
});
test('principal uses only the verified document own session and ignores download sources',async()=>{
 const f=await fixture();await f.timers[1]();
 assert.equal(f.requests.length,1);assert.equal(f.requests[0].options.credentials,'same-origin');
 assert.equal(f.requests[0].options.body.get('video_id'),'3');assert.equal(f.opened.length,1);
 assert.equal(f.requests[0].options.headers['X-Page-Token'],'own-current-session');
 assert.equal(new Headers(f.requests[0].options.headers).has('Cookie'),false);
});
test('next episode uses the canonical requested episode instead of replaying the lab first episode',async()=>{
 const f=await fixture({path:'/serie/71225/1/2'});await f.timers[1]();assert.deepEqual(f.episodes,[22]);
});
test('authorization denial and foreign player URLs remain manual without repeated source requests',async()=>{
 for(const options of [{status:403},{target:'https://evil.invalid/player'}]){
  const f=await fixture(options);await f.timers[1]();await f.timers[1]();
  assert.equal(f.opened.length,0);assert.equal(f.requests.length,1);assert(f.notices.includes('manual'));
 }
});
test('a different source title cannot use the selected episode session',async()=>{
 const f=await fixture({path:'/serie/99999/1/1'});assert.equal(f.timers.length,1);assert.equal(f.requests.length,0);
});
test('magnet details stay available for selecting 1080p without a reload loop',async()=>{
 const f=await fixture({origin:app,path:'/titulo/jogos-mortais-3',config:{id:'magnet',sourceType:'torrent'}});
 assert.equal(f.timers.length,1);assert.equal(f.navigations.length,0);assert(f.notices.includes('magnet'));
});
test('catalogue selection uses the public title slug and the selected season source, never another provider',async()=>{
 const f=await fixture({origin:app,path:'/',config:{id:'mediafire',sourceType:'mediafire',season:2,episode:1}});
 const calls=[],stream='212c4514-8d41-4ed5-b2b4-c152bc74bd53';
 f.context.fetch=async url=>{
  calls.push(url);
  if(url.startsWith('/api/v1/search?'))return Response.json({data:{items:[{id:'title-uuid',slug:'meu-nome-e-farah',name:'Meu Nome é Farah'}]}});
  if(url==='/api/v1/titles/meu-nome-e-farah')return Response.json({data:{id:'title-uuid',slug:'meu-nome-e-farah',kind:'series'}});
  if(url==='/api/v1/titles/title-uuid/seasons')return Response.json({data:[{season_number:2,episodes:[{episode_number:1,streams:[{id:'wrong-provider',source_type:'google_drive'},{id:stream,source_type:'mediafire'}]}]}]});
  throw Error('Unexpected catalogue path');
 };
 await f.timers[1]();assert.equal(calls[1],'/api/v1/titles/meu-nome-e-farah');
 assert.deepEqual(f.navigations,['/assistir/'+stream]);
});
