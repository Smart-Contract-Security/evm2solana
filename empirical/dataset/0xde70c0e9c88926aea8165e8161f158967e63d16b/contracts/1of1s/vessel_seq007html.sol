// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./base64.sol";
import "./IFileStore.sol";

interface IVessel {
    function vaultToEntry(uint _tokenId, uint _entry) external view returns (bytes memory) ;
}

interface IRelics {
    function relicToPayload(uint256 tokenId) external view returns (bytes memory);
}

interface INoteSampleMapV2 {
    function noteToSampleCraft(uint8 midiNote) external view returns (uint256);
}

contract The_Long_Drift_html {
    using Base64 for bytes;

    error InvalidPieceLength();
    error MissingSample(uint8 midiNote);

    IVessel public immutable vessel;
    IRelics public immutable relics;
    INoteSampleMapV2 public immutable noteSampleMap;
    IFileStore public immutable fileStore;

    uint256 public constant RECORD_SIZE = 7;

    constructor() {
        relics = IRelics(0x48cB121Fa84b7C08692e74872D044B15369977CD);
        vessel = IVessel(0xECb92Cc7112b80A2234936315BbB493fb48d1463);
        fileStore = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);
        noteSampleMap = INoteSampleMapV2(0xC0dD3e458E841aA4508BB65d9eBaf6e7701d5246);
    }

    function renderHTML(uint256 pieceCraftId) external view returns (string memory) {
        bytes memory piece = vessel.vaultToEntry(pieceCraftId, 0);
        if (piece.length % RECORD_SIZE != 0) revert InvalidPieceLength();

        bool[128] memory used;
        _collectUsedNotes(piece, used);

        string memory pieceHex = _hex(piece);
        string memory sampleEntries = _buildSampleEntries(used);

        return string.concat(
            _html1(),
            getTonejs(),
            _html2(),
            'const pieceHex="0x', pieceHex, '";',
            'const sampleMap={', sampleEntries, '};',
            _html3()
        );
    }

    function renderScript(uint256 pieceCraftId) external view returns (string memory) {
        bytes memory piece = vessel.vaultToEntry(pieceCraftId, 0);
        if (piece.length % RECORD_SIZE != 0) revert InvalidPieceLength();

        bool[128] memory used;
        _collectUsedNotes(piece, used);

        string memory pieceHex = _hex(piece);
        string memory sampleEntries = _buildSampleEntries(used);

        return string.concat(
            'const pieceHex="0x', pieceHex, '";',
            'const sampleMap={', sampleEntries, '};'
        );
    }

    function _collectUsedNotes(bytes memory piece, bool[128] memory used) internal pure {
        uint256 count = piece.length / RECORD_SIZE;
        for (uint256 i = 0; i < count; ++i) {
            used[uint8(piece[i * RECORD_SIZE])] = true;
        }
    }

    function _buildSampleEntries(bool[128] memory used)
        internal
        view
        returns (string memory)
    {
        uint256 count;

        for (uint256 note; note < 128; ++note) {
            if (used[note]) ++count;
        }

        if (count == 0) return "";

        string[] memory noteStrings = new string[](count);
        string[] memory b64s = new string[](count);

        bytes memory mid = bytes('":"data:audio/mpeg;base64,');
        uint256 totalLen;

        uint256 j;
        for (uint256 note; note < 128; ++note) {
            if (!used[note]) continue;

            uint256 sampleCraftId = noteSampleMap.noteToSampleCraft(uint8(note));
            if (sampleCraftId == 0) revert MissingSample(uint8(note));

            bytes memory mp3 = relics.relicToPayload(sampleCraftId);

            string memory noteStr = _u(note);
            string memory b64 = mp3.encode();

            noteStrings[j] = noteStr;
            b64s[j] = b64;

            // comma except first
            if (j != 0) totalLen += 1;

            // " + note + ":"data:audio/mpeg;base64, + b64 + "
            totalLen += 1 + bytes(noteStr).length + mid.length + bytes(b64).length + 1;

            unchecked {
                ++j;
            }
        }

        bytes memory out = new bytes(totalLen);
        uint256 k;

        for (uint256 i; i < count; ++i) {
            if (i != 0) {
                out[k++] = ",";
            }

            out[k++] = '"';

            bytes memory n = bytes(noteStrings[i]);
            for (uint256 a; a < n.length; ++a) {
                out[k++] = n[a];
            }

            for (uint256 a; a < mid.length; ++a) {
                out[k++] = mid[a];
            }

            bytes memory b = bytes(b64s[i]);
            for (uint256 a; a < b.length; ++a) {
                out[k++] = b[a];
            }

            out[k++] = '"';
        }

        return string(out);
    }

    function _html1() internal pure returns (string memory) {
        return '<!doctype html><html lang=en><head><meta charset=UTF-8><meta name=viewport content="width=device-width,initial-scale=1"><title>The Long Drift</title>';
    }

    function _html2() internal pure returns (string memory) {
        return "<style>html,body{margin:0;padding:0;overflow:hidden;background:#050507}canvas{display:block}#audioPlay{position:fixed;left:50%;bottom:8%;width:58px;height:50px;border:0 solid rgba(236,231,223,0.24);background:rgba(10,11,14,0.56);backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);border-radius:5px;cursor:pointer;z-index:20;display:grid;place-items:center;padding:0;transition:opacity 160ms ease,transform 160ms ease,background 160ms ease;box-shadow:0 10px 30px rgba(0,0,0,0.26)}#audioPlay:hover{background:rgba(22,24,29,0.68);transform:translateY(-1px)}#audioPlay:active{transform:translateY(0) scale(0.98)}#audioPlay .tri{width:0;height:0;border-top:11px solid transparent;border-bottom:11px solid transparent;border-left:17px solid rgba(236,231,223,0.88);margin-left:4px;filter:drop-shadow(0 0 8px rgba(236,231,223,0.14))}#audioPlay.loading .tri{opacity:0.45}#audioPlay.playing{opacity:0.36;pointer-events:none}</style></head><body><canvas id=c></canvas><button id=audioPlay aria-label='Play audio'><span class=tri></span></button><script>const CONFIG={starCount:260,driftSpeed:0.42,gentleBoost:2.1,parallaxDepth:5,windowScale:0.869,windowCornerRadius:64,glassReflection:true,dustCount:38,nebulaCount:40,nebulaAmount:16,gradientBands:15,targetFps:30,};const canvas=document.getElementById('c');const ctx=canvas.getContext('2d',{alpha:false});let width=0;let height=0;let frame=0;let stars=[];let dust=[];let farClouds=[];let boost=false;let shipSway=0;let lastTime=0;let frameInterval=1000/CONFIG.targetFps;let dpr=1;function rand(min,max){return Math.random()*(max-min)+min;}function choice(arr){return arr[Math.floor(Math.random()*arr.length)];}function clamp(v,lo,hi){return Math.max(lo,Math.min(hi,v));}function lerp(a,b,t){return a+(b-a)*t;}function mapRange(v,inMin,inMax,outMin,outMax,shouldClamp=false){const n=(v-inMin)/(inMax-inMin);const val=outMin+n*(outMax-outMin);return shouldClamp?clamp(val,Math.min(outMin,outMax),Math.max(outMin,outMax)):val;}function rgba(r,g,b,a){return`rgba(${r},${g},${b},${clamp(a / 255, 0, 1)})`;}function resize(){width=window.innerWidth;height=window.innerHeight;canvas.width=Math.floor(width*dpr);canvas.height=Math.floor(height*dpr);canvas.style.width=width+'px';canvas.style.height=height+'px';ctx.setTransform(dpr,0,0,dpr,0,0);if(!stars.length)resetStars();if(!dust.length)resetDust();}function resetStars(){stars=[];for(let i=0;i<CONFIG.starCount;i++)stars.push(makeStar());}function resetDust(){dust=[];for(let i=0;i<CONFIG.dustCount;i++){dust.push({x:rand(0,width),y:rand(0,height),r:rand(0.35,1.5),a:rand(10,45),drift:rand(0.004,0.018),});}}function makeStar(){return{x:rand(0,width),y:rand(0,height),z:rand(0.25,CONFIG.parallaxDepth),size:rand(0.45,2.15),tone:choice([175,200,225,245,255]),twinkle:rand(0,Math.PI*2),verticalDrift:rand(-0.018,0.018),};}function resetStar(s,fromRight=true){s.x=fromRight?width+rand(20,260):rand(-260,-20);s.y=rand(0,height);s.z=rand(0.25,CONFIG.parallaxDepth);s.size=rand(0.45,2.15);s.tone=choice([175,200,225,245,255]);s.twinkle=rand(0,Math.PI*2);s.verticalDrift=rand(-0.018,0.018);}function windowBounds(){const w=width*CONFIG.windowScale;const h=height*CONFIG.windowScale*0.66;return{x:width/2-w/2,y:height/2-h/2,w,h,r:CONFIG.windowCornerRadius,};}function windowEdgeFalloff(x,y){const b=windowBounds();const inset=24;const inside=x>b.x+inset&&x<b.x+b.w-inset&&y>b.y+inset&&y<b.y+b.h-inset;if(!inside)return 0;const dx=Math.min(x-b.x,b.x+b.w-x);const dy=Math.min(y-b.y,b.y+b.h-y);return clamp(Math.min(dx,dy)/96,0,1);}function roundedRectPath(x,y,w,h,r){ctx.moveTo(x+r,y);ctx.lineTo(x+w-r,y);ctx.quadraticCurveTo(x+w,y,x+w,y+r);ctx.lineTo(x+w,y+h-r);ctx.quadraticCurveTo(x+w,y+h,x+w-r,y+h);ctx.lineTo(x+r,y+h);ctx.quadraticCurveTo(x,y+h,x,y+h-r);ctx.lineTo(x,y+r);ctx.quadraticCurveTo(x,y,x+r,y);}function draw(){frame++;const t=frame*0.006;const speed=CONFIG.driftSpeed;shipSway=lerp(shipSway,boost?0.7:0.35,0.025);ctx.fillStyle='rgb(3,3,4)';ctx.fillRect(0,0,width,height);drawSideDriftingStars(speed,t);drawWindowMask();}function drawSideDriftingStars(speed,t){const shakeX=Math.sin(t*1.7)*shipSway;const shakeY=Math.cos(t*1.1)*shipSway;ctx.save();ctx.translate(shakeX,shakeY);ctx.lineCap='round';for(const s of stars){const depthSpeed=speed/s.z;const oldX=s.x;const oldY=s.y;s.x-=depthSpeed;s.y+=s.verticalDrift+Math.sin(t+s.twinkle)*0.006;if(s.x<-40)resetStar(s,true);if(s.y<-30)s.y=height+30;if(s.y>height+30)s.y=-30;const edge=windowEdgeFalloff(s.x,s.y);if(edge<=0)continue;const twinkle=0.82+0.18*Math.sin(frame*0.018+s.twinkle);const alpha=mapRange(s.z,0.25,CONFIG.parallaxDepth,230,55,true)*edge*twinkle;const strokeW=mapRange(s.z,0.25,CONFIG.parallaxDepth,1.8,0.35,true)*s.size;ctx.strokeStyle=rgba(s.tone,s.tone,s.tone,alpha);ctx.lineWidth=strokeW;ctx.beginPath();if(boost&&s.z<1.15){ctx.moveTo(oldX,oldY);ctx.lineTo(s.x,s.y);}else if(s.z<0.7&&speed>0.7){ctx.moveTo(oldX,oldY);ctx.lineTo(s.x,s.y);}else{ctx.moveTo(s.x,s.y);ctx.lineTo(s.x+0.01,s.y+0.01);}ctx.stroke();}ctx.restore();}function drawWindowMask(){const b=windowBounds();ctx.save();ctx.beginPath();ctx.rect(0,0,width,height);roundedRectPath(b.x,b.y,b.w,b.h,b.r);ctx.fillStyle='rgba(0,0,0,1)';ctx.fill('evenodd');ctx.restore();}function strokeRoundRect(x,y,w,h,r,color,lineWidth){ctx.strokeStyle=color;ctx.lineWidth=lineWidth;ctx.beginPath();roundedRectPath(x,y,w,h,r);ctx.stroke();}function loop(now=0){requestAnimationFrame(loop);if(now-lastTime<frameInterval)return;lastTime=now-((now-lastTime)%frameInterval);draw();}window.addEventListener('keydown',(e)=>{if(e.key===' '){boost=!boost;e.preventDefault();}if(e.key==='s'||e.key==='S')saveStill();});window.addEventListener('resize',resize);resize();loop();</script><script>(()=>{";
    }
    
    function _html3() internal pure returns (string memory) {
        return "const playButton=document.getElementById('audioPlay');let sampler,delay,reverb;let loaded=false;let loadingPromise=null;let playing=false;let stopTimer=0;const midiToNote=n=>Tone.Frequency(n,'midi').toNote();function hexToBytes(hex){const s=hex.startsWith('0x')?hex.slice(2):hex;const out=new Uint8Array(s.length/2);for(let i=0;i<s.length;i+=2)out[i/2]=parseInt(s.slice(i,i+2),16);return out;}function decodePiece7(hex){const bytes=hexToBytes(hex);if(bytes.length%7!==0)throw new Error('bad piece length');const events=[];for(let i=0;i<bytes.length;i+=7){const n=bytes[i];const t=(bytes[i+1]<<16)|(bytes[i+2]<<8)|bytes[i+3];const d=(bytes[i+4]<<8)|bytes[i+5];const v=bytes[i+6];events.push({n,t,d:Math.max(d,20),v:Math.max(v/127,0.02)});}return events.sort((a,b)=>a.t-b.t||a.n-b.n);}const piece=decodePiece7(pieceHex);const samplerUrls={};for(const k in sampleMap)samplerUrls[midiToNote(Number(k))]=sampleMap[k];const totalSec=piece.reduce((m,e)=>Math.max(m,(e.t+e.d)/1000),0);async function buildAudio(){if(loaded)return;if(loadingPromise)return loadingPromise;playButton.classList.add('loading');loadingPromise=new Promise(async(resolve,reject)=>{try{await Tone.start();Tone.Destination.volume.value=-6;if(reverb)reverb.dispose();if(delay)delay.dispose();if(sampler)sampler.dispose();delay=new Tone.FeedbackDelay(0.25,0.08);reverb=new Tone.Reverb({decay:3.6,wet:0.42,preDelay:0.02});sampler=new Tone.Sampler({urls:samplerUrls,release:1.2,onload:()=>{loaded=true;playButton.classList.remove('loading');resolve();},onerror:reject});sampler.chain(delay,reverb,Tone.Destination);}catch(err){playButton.classList.remove('loading');reject(err);}});return loadingPromise;}function stopAudio(){playing=false;playButton.classList.remove('playing');if(stopTimer)clearTimeout(stopTimer);}playButton.addEventListener('click',async(e)=>{e.preventDefault();if(playing)return;try{await buildAudio();playing=true;playButton.classList.add('playing');const now=Tone.now()+0.08;for(const ev of piece)sampler.triggerAttackRelease(midiToNote(ev.n),ev.d/1000,now+ev.t/1000,ev.v);stopTimer=setTimeout(stopAudio,Math.ceil(totalSec*1000)+1200);}catch(err){console.error(err);playButton.classList.remove('loading','playing');}});})();</script></body></html>";
    }

    function _hex(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = '0123456789abcdef';
        bytes memory str = new bytes(data.length * 2);
        for (uint256 i = 0; i < data.length; ++i) {
            str[2 * i] = alphabet[uint8(data[i] >> 4)];
            str[2 * i + 1] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    function _u(uint256 x) internal pure returns (string memory) {
        if (x == 0) return '0';
        uint256 j = x;
        uint256 len;
        while (j != 0) {
            ++len;
            j /= 10;
        }
        bytes memory b = new bytes(len);
        while (x != 0) {
            len--;
            b[len] = bytes1(uint8(48 + x % 10));
            x /= 10;
        }
        return string(b);
    }

    function getTonejs() public view returns (string memory) {
        return string.concat(
            "<script type=\"text/javascript+gzip\" src=\"data:text/javascript;base64,",
            fileStore.getFile("Tone.js.gz").read(),
            "\"></script>",
            getUNZIP()
        );
    }

    function getUNZIP() internal view returns (string memory) {
        return string.concat(
            "<script src=\"data:text/javascript;base64,",
            fileStore.getFile("gunzipScripts-0.0.1.js").read(),
            "\"></script>"
        );
    }

    function debugSampleIds(uint256 pieceCraftId)
        external
        view
        returns (uint8[] memory notes, uint256[] memory sampleCraftIds)
    {
        bytes memory piece = vessel.vaultToEntry(pieceCraftId, 0);
        if (piece.length % RECORD_SIZE != 0) revert InvalidPieceLength();

        bool[128] memory used;
        _collectUsedNotes(piece, used);

        uint256 count;
        for (uint256 note; note < 128; ++note) {
            if (used[note]) count++;
        }

        notes = new uint8[](count);
        sampleCraftIds = new uint256[](count);

        uint256 j;
        for (uint256 note; note < 128; ++note) {
            if (!used[note]) continue;

            notes[j] = uint8(note);
            sampleCraftIds[j] = noteSampleMap.noteToSampleCraft(uint8(note));

            unchecked {
                ++j;
            }
        }
    }
}
