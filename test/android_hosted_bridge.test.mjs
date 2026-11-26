import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
const code=await readFile(new URL('../assets/android_hosted_bridge.js',import.meta.url),'utf8');
function fixture(binary=true){
 const messages=[],reads=[];
 const bridge={postMessage:m=>messages.push(m)};
 const target={epoch:'owned-epoch'};
 const window={bechiHosted:bridge,__bechiHostedTarget:target,
  __bechiReadHosted:async(...args)=>{reads.push(args);return{status:206,type:'video/mp4',range:'bytes 0-2/30',data:binary?new Uint8Array([1,2,3]).buffer:'AQID'};},
  __bechiConfigureHosted:next=>{window.__bechiHostedTarget=next;}};
 vm.runInNewContext(code.replaceAll('__BECHI_BINARY__',String(binary)),{window,location:{href:'https://abyssplayer.com/own-id'},TextEncoder,Uint8Array,DataView,ArrayBuffer,JSON});
 window.__bechiAndroidPost({type:'ready',epoch:target.epoch,document:'own-frame'});
 return{window,bridge,messages,reads};
}
test('Android bridge correlates binary bytes with the exact source document and request',async()=>{
 const f=fixture();await f.bridge.onmessage({data:JSON.stringify({type:'read',epoch:'owned-epoch',request:'owned-read',url:'https://media.example/own.mp4',range:'bytes=0-2'})});
 const packet=f.messages.at(-1),length=new DataView(packet).getUint32(0,true);
 const header=JSON.parse(new TextDecoder().decode(new Uint8Array(packet,4,length)));
 assert.equal(header.request,'owned-read');assert.equal(header.document,'own-frame');assert.equal(header.payload.status,206);
 assert.deepEqual([...new Uint8Array(packet,4+length)],[1,2,3]);assert.equal(f.reads[0][2],true);
});
test('older Android WebViews use the same bounded base64 response protocol',async()=>{
 const f=fixture(false);await f.bridge.onmessage({data:JSON.stringify({type:'read',epoch:'owned-epoch',request:'owned-read',url:'https://media.example/own.mp4'})});
 const response=JSON.parse(f.messages.at(-1));assert.equal(response.payload.data,'AQID');assert.equal(response.epoch,'owned-epoch');assert.equal(f.reads[0][2],false);
});
test('an old source cannot issue reads after its episode has been replaced',async()=>{
 const f=fixture();await f.bridge.onmessage({data:JSON.stringify({type:'configure',target:{epoch:'next-episode'}})});
 await f.bridge.onmessage({data:JSON.stringify({type:'read',epoch:'owned-epoch',request:'old-read',url:'https://media.example/own.mp4'})});
 assert.equal(f.reads.length,0);assert.equal(f.window.__bechiHostedTarget.epoch,'next-episode');
});
