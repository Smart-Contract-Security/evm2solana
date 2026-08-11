// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

// 24Punks Renderer 2 — Face (eyes, nose, mouth, skin)
contract Punks24R2 {

    function renderHead(uint256 id) external pure returns (string memory) {
        string memory sk = _sk(id);
        // Head: cols 7-16, rows 7-19 + ears
        string memory a = '';
        for(uint256 y=7;y<=19;y++){
            for(uint256 x=7;x<=16;x++){
                a = string(abi.encodePacked(a, _p(x,y,sk)));
            }
        }
        // Ears
        a = string(abi.encodePacked(a,_p(6,13,sk),_p(6,14,sk),_p(17,13,sk),_p(17,14,sk)));
        return a;
    }

    function renderFace(uint256 id) external pure returns (string memory) {
        uint256 ti = _r(id,4) % 6;
        string memory s = '';
        s = string(abi.encodePacked(s, _renderEyes(id, ti)));
        s = string(abi.encodePacked(s, _renderNose(id, ti)));
        s = string(abi.encodePacked(s, _renderMouth(id, ti)));
        if(_r(id,30)%4!=0) s = string(abi.encodePacked(s, _renderBrows(ti)));
        if(_r(id,31)%3==0) s = string(abi.encodePacked(s, _renderBlush()));
        if(_r(id,32)%5==0) s = string(abi.encodePacked(s, _renderMole()));
        return s;
    }

    function renderExtras(uint256 id) external pure returns (string memory) {
        string memory s = '';
        // Earring ~30%
        if(_r(id,33)%3==0) s=string(abi.encodePacked(s,_p(6,14,'#FFD700'),_p(6,15,'#FFD700'),_p(6,16,'#FFD700')));
        // Smoke ~18%
        if(_r(id,34)%6==0) s=string(abi.encodePacked(s,_p(16,17,'#F5F5DC'),_p(17,17,'#F5F5DC'),_p(18,17,'#FF4500'),_p(18,16,'#888'),_p(19,15,'#666')));
        // Laser eyes ~6%
        if(_r(id,35)%17==0){
            for(uint256 x=0;x<7;x++) s=string(abi.encodePacked(s,_p(x,12,'#FF0000')));
            for(uint256 x=17;x<24;x++) s=string(abi.encodePacked(s,_p(x,12,'#FF0000')));
        }
        return s;
    }

    function renderNeck(uint256 id) external pure returns (string memory) {
        string memory sk = _sk(id);
        string memory s = string(abi.encodePacked(_p(10,20,sk),_p(11,20,sk),_p(12,20,sk),_p(13,20,sk),_p(10,21,sk),_p(11,21,sk),_p(12,21,sk),_p(13,21,sk)));
        // Necklace
        uint256 ni = _r(id,36)%4;
        if(ni==1){ // gold chain
            for(uint256 x=9;x<=14;x++) s=string(abi.encodePacked(s,_p(x,20,'#FFD700')));
            s=string(abi.encodePacked(s,_p(11,21,'#FFD700'),_p(12,21,'#FFD700')));
        } else if(ni==2){ // silver
            for(uint256 x=9;x<=14;x++) s=string(abi.encodePacked(s,_p(x,20,'#C0C0C0')));
        } else if(ni==3){ // bandana
            for(uint256 x=8;x<=15;x++) s=string(abi.encodePacked(s,_p(x,20,'#CC0000'),_p(x,21,'#CC0000')));
        }
        return s;
    }

    function renderBody(uint256 id) external pure returns (string memory) {
        string memory sk = _sk(id);
        uint256 si = _r(id,37)%6;
        string memory sc;
        if(si==0)sc='#2244AA';else if(si==1)sc='#AA2222';else if(si==2)sc='#22AA22';
        else if(si==3)sc='#AA8822';else if(si==4)sc='#333333';else sc='#882288';
        string memory s = '';
        for(uint256 x=4;x<=19;x++) s=string(abi.encodePacked(s,_p(x,22,sc),_p(x,23,sc)));
        // Collar
        s=string(abi.encodePacked(s,_p(10,22,sk),_p(11,22,sk),_p(12,22,sk),_p(13,22,sk)));
        return s;
    }

    // Trait names
    function skinName(uint256 id) external pure returns(string memory){
        uint256 ti=_r(id,4)%6;
        if(ti==0){
            uint256 si=_r(id,5)%6;
            if(si==0)return"Light";if(si==1)return"Fair";if(si==2)return"Tan";
            if(si==3)return"Dark";if(si==4)return"Brown";return"Peach";
        }
        if(ti==1)return"Zombie";if(ti==2)return"Alien";
        if(ti==3)return"Ape";if(ti==4)return"Robot";return"Ghost";
    }
    function typeName(uint256 id) external pure returns(string memory){
        uint256 i=_r(id,4)%6;
        if(i==0)return"Human";if(i==1)return"Zombie";if(i==2)return"Alien";
        if(i==3)return"Ape";if(i==4)return"Robot";return"Ghost";
    }
    function neckName(uint256 id) external pure returns(string memory){
        uint256 i=_r(id,36)%4;
        if(i==0)return"None";if(i==1)return"Gold Chain";if(i==2)return"Silver Chain";return"Bandana";
    }
    function shirtName(uint256 id) external pure returns(string memory){
        uint256 i=_r(id,37)%6;
        if(i==0)return"Blue";if(i==1)return"Red";if(i==2)return"Green";
        if(i==3)return"Gold";if(i==4)return"Black";return"Purple";
    }

    // Internal face rendering
    function _renderEyes(uint256 id, uint256 ti) private pure returns(string memory){
        if(ti==2){ // Alien big eyes
            string memory ec=_ec(id);
            return string(abi.encodePacked(
                _p(7,11,'#000'),_p(8,11,'#000'),_p(9,11,'#000'),_p(7,12,'#000'),_p(8,12,ec),_p(9,12,'#000'),_p(7,13,'#000'),_p(8,13,'#000'),_p(9,13,'#000'),
                _p(13,11,'#000'),_p(14,11,'#000'),_p(15,11,'#000'),_p(13,12,'#000'),_p(14,12,ec),_p(15,12,'#000'),_p(13,13,'#000'),_p(14,13,'#000'),_p(15,13,'#000')
            ));
        }
        if(ti==4){ // Robot
            return string(abi.encodePacked(_p(8,12,'#00FF00'),_p(9,12,'#00FF00'),_p(13,12,'#FF2200'),_p(14,12,'#FF2200')));
        }
        string memory ec=_ec(id);
        return string(abi.encodePacked(
            _p(7,12,'#000'),_p(8,12,ec),_p(9,12,'#000'),_p(7,12,'#fff'),
            _p(13,12,'#000'),_p(14,12,ec),_p(15,12,'#000'),_p(13,12,'#fff')
        ));
    }
    function _renderBrows(uint256 ti) private pure returns(string memory){
        if(ti==2||ti==4) return '';
        return string(abi.encodePacked(_p(7,11,'#000'),_p(8,11,'#000'),_p(9,11,'#000'),_p(10,11,'#000'),_p(13,11,'#000'),_p(14,11,'#000'),_p(15,11,'#000'),_p(16,11,'#000')));
    }
    function _renderNose(uint256 id, uint256 ti) private pure returns(string memory){
        if(ti==4) return '';
        string memory nc=_r(id,5)%3==0?'#bb8844':'#00000033';
        return string(abi.encodePacked(_p(11,15,nc),_p(12,15,nc)));
    }
    function _renderMouth(uint256 id, uint256 ti) private pure returns(string memory){
        if(ti==4) return string(abi.encodePacked(_p(8,17,'#445566'),_p(9,17,'#00FF00'),_p(10,17,'#445566'),_p(11,17,'#00FF00'),_p(12,17,'#445566'),_p(13,17,'#00FF00'),_p(14,17,'#445566'),_p(15,17,'#445566')));
        bool lip=_r(id,38)%4==0;
        string memory lc=lip?'#CC0000':'#cc5555';
        return string(abi.encodePacked(_p(8,17,'#000'),_p(9,17,lc),_p(10,17,'#fff'),_p(11,17,'#fff'),_p(12,17,'#fff'),_p(13,17,'#fff'),_p(14,17,lc),_p(15,17,'#000')));
    }
    function _renderBlush() private pure returns(string memory){
        return string(abi.encodePacked(_p(6,14,'#ffaaaa'),_p(17,14,'#ffaaaa')));
    }
    function _renderMole() private pure returns(string memory){
        return _p(15,15,'#5a3a1a');
    }

    function _sk(uint256 id) private pure returns(string memory){
        uint256 ti=_r(id,4)%6;
        if(ti==1)return"#6DBF45";if(ti==2)return"#88DDBB";
        if(ti==3)return"#7B3F00";if(ti==4)return"#9BAEBF";if(ti==5)return"#C0C0EE";
        uint256 si=_r(id,5)%6;
        if(si==0)return"#e8b88a";if(si==1)return"#f5cba7";if(si==2)return"#c68642";
        if(si==3)return"#8d5524";if(si==4)return"#d4956a";return"#ffdbac";
    }
    function _ec(uint256 id) private pure returns(string memory){
        uint256 i=_r(id,6)%6;
        if(i==0)return"#5b8dd9";if(i==1)return"#3aaa5a";if(i==2)return"#dd6633";
        if(i==3)return"#8833cc";if(i==4)return"#cc2266";return"#ddaa00";
    }
    function _r(uint256 id,uint256 s) private pure returns(uint256){return uint256(keccak256(abi.encodePacked(id,s)));}
    function _p(uint256 x,uint256 y,string memory c) private pure returns(string memory){
        uint256 px=x*10;uint256 py=y*10;
        return string(abi.encodePacked('<rect x="',_n(px),'" y="',_n(py),'" width="10" height="10" fill="',c,'"/>'));
    }
    function _n(uint256 v) private pure returns(string memory){
        if(v==0)return"0";
        if(v<10)return string(abi.encodePacked(bytes1(uint8(48+v))));
        if(v<100)return string(abi.encodePacked(bytes1(uint8(48+v/10)),bytes1(uint8(48+v%10))));
        if(v<1000)return string(abi.encodePacked(bytes1(uint8(48+v/100)),bytes1(uint8(48+v/10%10)),bytes1(uint8(48+v%10))));
        return string(abi.encodePacked(bytes1(uint8(48+v/1000)),bytes1(uint8(48+v/100%10)),bytes1(uint8(48+v/10%10)),bytes1(uint8(48+v%10))));
    }








}