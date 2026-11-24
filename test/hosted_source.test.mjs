import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
const script=await readFile(new URL('../assets/hosted_source.js',import.meta.url),'utf8');
function run({kind='superflix',host='superflixapi.boats',path='/serie/246992',principal='https://xn--80adalaab0boiodbce7addhh.delivery/video/'+'a'.repeat(32),checkbox=false}={}){
 const messages=[],opens=[],requests=[],clicks=[];
 const target={kind,epoch:'own-test-epoch',root:'https://superflixapi.boats/serie/246992',url:kind==='c7'?'https://abyssplayer.com/iwBlab3Rj':'https://superflixapi.boats/serie/246992/1/1',expectedTitle:'Sereias',season:1,episode:1};
 const document={title:kind==='c7'?'Berlim T01_EP-01_Dublado_1080p.mp4':'Sereias',querySelector(selector){if(selector==='.jwplayer[id]'&&(kind==='c7'||host!=='superflixapi.boats'))return{id:'video'};if(checkbox&&selector.includes('checkbox'))return{getClientRects:()=>[{}],click:()=>clicks.push(true)};return null;},querySelectorAll:()=>[],addEventListener:()=>{}};
 const window={__bechiHostedTarget:target,webkit:{messageHandlers:{bechiHosted:{postMessage:m=>messages.push(m)}}},ALL_EPISODES:{1:[{ID:123,epi_num:1}]},fetchBootstrapOptions:(id,done)=>done([{ID:90,type:'1',is_fake:true},{ID:91,type:'2'},{ID:92,type:'1'}]),requirePageTokenClient:()=> 'normal-page-fixture',sfEdgeHeaders:()=>({'X-Own-Page':'fixture'}),API_URL_SOURCE:'/player/source',CSRF_TOKEN:'page-csrf-fixture',renderEpisodes:()=>{},closePlayer:()=>{},openIframe:(...args)=>opens.push(args),jwplayer:()=>({getConfig:()=>({title:'Sereias 1x1'}),getPlaylistItem:()=>({sources:[{file:'https://media.example/own.m3u8',label:'1080p',type:'hls'}]}),pause:()=>{},setMute:()=>{}})};
 const context={window,document,location:{hostname:host,origin:'https://'+host,pathname:path},crypto:webcrypto,URL,URLSearchParams,AbortSignal,AbortController,Uint8Array,btoa,clearTimeout,setInterval:()=>1,setTimeout:(fn,ms)=>ms===0?setTimeout(fn,0):setTimeout(fn,Math.min(ms,100)),fetch:async(url,options)=>{requests.push({url,options});return Response.json({data:{video_url:principal,fireplayer_ad_control:{normal:true}}});}};
 vm.runInNewContext(script,context);return{messages,opens,requests,clicks,window};
}
test('SuperFlix selects principal with the real page APIs without opening a chooser',async()=>{
 const r=run();await new Promise(resolve=>setTimeout(resolve,20));
 assert.equal(r.requests.length,1);assert.equal(r.requests[0].url,'/player/source');assert.equal(r.requests[0].options.body.get('video_id'),'92');assert.equal(r.opens.length,1);assert(r.messages.some(m=>m.type==='validated'));assert.equal(r.window.open(),null);
});
test('source rejection preserves failure instead of opening an unapproved player',async()=>{
 const r=run({principal:'https://foreign.example/player'});await new Promise(resolve=>setTimeout(resolve,20));assert.equal(r.opens.length,0);assert(r.messages.some(m=>m.type==='failure'));
});
test('C7 exports media metadata for native playback',async()=>{
 const r=run({kind:'c7',host:'abyssplayer.com',path:'/iwBlab3Rj'});await new Promise(resolve=>setTimeout(resolve,20));const ready=r.messages.find(m=>m.type==='ready');assert.equal(ready.format,'mp4');assert.equal(ready.variants[0].height,1080);
});
test('a synthetic human checkbox is observed and never clicked by the adapter',async()=>{
 const r=run({host:'challenges.cloudflare.com',path:'/own-fixture',checkbox:true});await new Promise(resolve=>setTimeout(resolve,20));assert(r.messages.some(m=>m.type==='human'));assert.equal(r.clicks.length,0);assert.equal(r.requests.length,0);
});
