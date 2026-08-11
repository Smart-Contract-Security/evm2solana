// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

// 24Punks Renderer 3 — Accessories + Beard + Moustache
contract Punks24R3 {

    function renderAcc(uint256 id) external pure returns (string memory) {
        uint256 t = _r(id,7) % 7;
        if(t==0) return "";
        if(t==1) return _shades();
        if(t==2) return _glasses3d();
        if(t==3) return "";
        if(t==4) return _monocle();
        if(t==5) return _eyepatch();
        return _nerdGlasses();
    }

    function renderBeard(uint256 id) external pure returns (string memory) {
        uint256 ti = _r(id,4) % 6;
        if(ti==2||ti==4||ti==5) return ""; // alien/robot/ghost no beard
        uint256 t = _r(id,8) % 5;
        if(t==0) return "";
        if(t==1) return _goatee();
        if(t==2) return _fullbeard();
        if(t==3) return _moustache();
        return _stubble();
    }

    function renderRareTraits(uint256 id) external pure returns (string memory) { return ""; }

    // Accessory styles
    function _shades() private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(6,12,'#000'),_p(7,12,'#000'),_p(8,12,'#000'),_p(9,12,'#000'),_p(13,12,'#000'),_p(14,12,'#000'),_p(15,12,'#000'),_p(16,12,'#000'),_p(10,12,'#222'),_p(11,12,'#222')));
        string memory b=string(abi.encodePacked(_p(12,12,'#222'),_p(6,11,'#FFD700'),_p(9,11,'#FFD700'),_p(13,11,'#FFD700'),_p(16,11,'#FFD700'),_p(6,13,'#FFD700'),_p(9,13,'#FFD700'),_p(13,13,'#FFD700'),_p(16,13,'#FFD700')));
        return string(abi.encodePacked(a,b));
    }
    function _glasses3d() private pure returns(string memory){
        return string(abi.encodePacked(
            '<rect x="60" y="110" width="40" height="30" fill="#FF0000" opacity="0.5"/>',
            '<rect x="130" y="110" width="40" height="30" fill="#0000FF" opacity="0.5"/>',
            '<rect x="100" y="120" width="30" height="10" fill="#333"/>',
            _p(6,12,'#888'),_p(16,12,'#888')
        ));
    }
    function _vr() private pure returns(string memory){ return ""; }
    function _monocle() private pure returns(string memory){
        return string(abi.encodePacked(_p(6,11,'#FFD700'),_p(9,11,'#FFD700'),_p(6,14,'#FFD700'),_p(9,14,'#FFD700'),_p(6,12,'#FFD700'),_p(6,13,'#FFD700'),_p(9,12,'#FFD700'),_p(9,13,'#FFD700'),_p(9,13,'#FFD700'),_p(10,13,'#FFD700'),_p(11,13,'#FFD700')));
    }
    function _eyepatch() private pure returns(string memory){
        return string(abi.encodePacked(
            '<rect x="50" y="110" width="50" height="30" fill="#111"/>',
            '<rect x="100" y="110" width="70" height="10" fill="#111"/>'
        ));
    }
    function _nerdGlasses() private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(7,12,'#333'),_p(8,12,'#333'),_p(9,12,'#333'),_p(13,12,'#333'),_p(14,12,'#333'),_p(15,12,'#333'),_p(10,12,'#555'),_p(11,12,'#555'),_p(12,12,'#555')));
        return string(abi.encodePacked(a,_p(7,11,'#888'),_p(9,11,'#888'),_p(13,11,'#888'),_p(15,11,'#888')));
    }

    // Beard styles
    function _goatee() private pure returns(string memory){
        return string(abi.encodePacked(_p(11,18,'#000'),_p(12,18,'#000'),_p(11,19,'#000'),_p(12,19,'#000')));
    }
    function _fullbeard() private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(7,18,'#000'),_p(8,18,'#000'),_p(9,18,'#000'),_p(10,18,'#000'),_p(11,18,'#000'),_p(12,18,'#000'),_p(13,18,'#000'),_p(14,18,'#000'),_p(15,18,'#000'),_p(16,18,'#000')));
        string memory b=string(abi.encodePacked(_p(7,19,'#000'),_p(8,19,'#000'),_p(9,19,'#000'),_p(10,19,'#000'),_p(11,19,'#000'),_p(12,19,'#000'),_p(13,19,'#000'),_p(14,19,'#000'),_p(15,19,'#000'),_p(16,19,'#000')));
        string memory cc=string(abi.encodePacked(_p(8,20,'#222'),_p(9,20,'#222'),_p(10,20,'#222'),_p(11,20,'#222'),_p(12,20,'#222'),_p(13,20,'#222'),_p(14,20,'#222'),_p(15,20,'#222')));
        return string(abi.encodePacked(a,b,cc));
    }
    function _moustache() private pure returns(string memory){
        return string(abi.encodePacked(_p(8,16,'#000'),_p(9,16,'#000'),_p(10,16,'#000'),_p(11,16,'#000'),_p(12,16,'#000'),_p(13,16,'#000'),_p(14,16,'#000'),_p(15,16,'#000')));
    }
    function _stubble() private pure returns(string memory){
        return string(abi.encodePacked(_p(7,18,'#555'),_p(10,18,'#555'),_p(13,18,'#555'),_p(16,18,'#555'),_p(9,19,'#555'),_p(12,19,'#555'),_p(15,19,'#555')));
    }

    // Trait names
    function accName(uint256 id) external pure returns(string memory){
        uint256 i=_r(id,7)%7;
        if(i==0)return"None";if(i==1)return"Shades";if(i==2)return"3D Glasses";
        if(i==3)return"VR Headset";if(i==4)return"Monocle";if(i==5)return"Eye Patch";
        return"Nerd Glasses";
    }
    function beardName(uint256 id) external pure returns(string memory){
        uint256 ti=_r(id,4)%6;
        if(ti==2||ti==4||ti==5) return"None";
        uint256 i=_r(id,8)%5;
        if(i==0)return"None";if(i==1)return"Goatee";if(i==2)return"Full Beard";
        if(i==3)return"Moustache";return"Stubble";
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