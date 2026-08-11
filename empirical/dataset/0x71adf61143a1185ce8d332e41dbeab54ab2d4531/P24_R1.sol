// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract Punks24R1 {

    function renderBg(uint256 id) external pure returns (string memory) {
        uint256 i=_r(id,1)%8;
        string memory c;
        if(i==0)c="#638596";else if(i==1)c="#b1a7a6";else if(i==2)c="#8b8c8d";
        else if(i==3)c="#5d6d7e";else if(i==4)c="#7d8a6a";else if(i==5)c="#6c5a4e";
        else if(i==6)c="#557766";else c="#665577";
        return string(abi.encodePacked('<rect width="240" height="240" fill="',c,'"/>'));
    }
    function renderHalo(uint256 id) external pure returns (string memory) {
        if(_r(id,20)%20!=0) return "";
        return string(abi.encodePacked(_p(7,1,'#FFD700'),_p(8,1,'#FFD700'),_p(9,1,'#FFD700'),_p(10,1,'#FFD700'),_p(11,1,'#FFD700'),_p(12,1,'#FFD700'),_p(13,1,'#FFD700'),_p(14,1,'#FFD700'),_p(15,1,'#FFD700'),_p(16,1,'#FFD700'),_p(6,2,'#FFD700'),_p(17,2,'#FFD700')));
    }
    function renderHorns(uint256 id) external pure returns (string memory) {
        if(_r(id,20)%20==0) return "";
        if(_r(id,21)%15!=0) return "";
        return string(abi.encodePacked(_p(7,2,'#8B0000'),_p(7,3,'#8B0000'),_p(8,3,'#8B0000'),_p(16,2,'#8B0000'),_p(16,3,'#8B0000'),_p(15,3,'#8B0000')));
    }
    function renderHair(uint256 id) external pure returns (string memory) {
        uint256 t=_r(id,2)%9; string memory h=_hc(id);
        if(t==0) return _mohawk(h);
        if(t==1) return _spiky(h);
        if(t==2) return _long(h);
        if(t==3) return _bun(h);
        if(t==4) return _wild(h);
        if(t==5) return "";
        if(t==6) return _cap(h);
        if(t==7) return _headband(h);
        return _stringy(h);
    }

    function renderHat(uint256 id) external pure returns(string memory){ return ""; }
    function bgName(uint256 id) external pure returns (string memory) {
        uint256 i=_r(id,1)%8;
        if(i==0)return"Steel Blue";if(i==1)return"Warm Grey";if(i==2)return"Cool Grey";
        if(i==3)return"Navy";if(i==4)return"Olive";if(i==5)return"Brown";
        if(i==6)return"Teal";return"Purple";
    }
    function hairName(uint256 id) external pure returns (string memory) {
        uint256 i=_r(id,2)%9;
        if(i==0)return"Mohawk";if(i==1)return"Spiky";if(i==2)return"Long";
        if(i==3)return"Bun";if(i==4)return"Wild";if(i==5)return"Bald";
        if(i==6)return"Cap";if(i==7)return"Headband";return"Stringy";
    }
    function hatName(uint256 id) external pure returns (string memory) {
        uint256 hair=_r(id,2)%9;
        if(hair==0||hair==4)return"None";
        uint256 i=_r(id,10)%5;
        if(i==0)return"None";if(i==1)return"Top Hat";if(i==2)return"Crown";
        if(i==3)return"Cowboy Hat";return"Beanie";
    }

    function _mohawk(string memory h) private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(11,2,h),_p(12,2,h),_p(10,3,h),_p(11,3,h),_p(12,3,h),_p(13,3,h)));
        string memory b=string(abi.encodePacked(_p(10,4,h),_p(11,4,h),_p(12,4,h),_p(13,4,h),_p(9,5,h),_p(10,5,h),_p(11,5,h),_p(12,5,h),_p(13,5,h),_p(14,5,h)));
        return string(abi.encodePacked(a,b));
    }
    function _spiky(string memory h) private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(7,7,h),_p(8,7,h),_p(9,7,h),_p(10,7,h),_p(11,7,h),_p(12,7,h),_p(13,7,h),_p(14,7,h),_p(15,7,h),_p(16,7,h)));
        string memory b=string(abi.encodePacked(_p(7,8,h),_p(8,8,h),_p(9,8,h),_p(10,8,h),_p(11,8,h),_p(12,8,h),_p(13,8,h),_p(14,8,h),_p(15,8,h),_p(16,8,h)));
        string memory c=string(abi.encodePacked(_p(8,6,h),_p(10,6,h),_p(12,6,h),_p(14,6,h),_p(16,6,h),_p(8,5,h),_p(10,5,h),_p(12,5,h),_p(14,5,h),_p(9,4,h),_p(13,4,h)));
        return string(abi.encodePacked(a,b,c));
    }
    function _long(string memory h) private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(7,6,h),_p(8,6,h),_p(9,6,h),_p(10,6,h),_p(11,6,h),_p(12,6,h),_p(13,6,h),_p(14,6,h),_p(15,6,h),_p(16,6,h)));
        string memory b=string(abi.encodePacked(_p(7,7,h),_p(8,7,h),_p(9,7,h),_p(10,7,h),_p(11,7,h),_p(12,7,h),_p(13,7,h),_p(14,7,h),_p(15,7,h),_p(16,7,h)));
        string memory c=string(abi.encodePacked(_p(7,8,h),_p(8,8,h),_p(9,8,h),_p(10,8,h),_p(11,8,h),_p(12,8,h),_p(13,8,h),_p(14,8,h),_p(15,8,h),_p(16,8,h)));
        string memory d=string(abi.encodePacked(_p(5,9,h),_p(6,9,h),_p(5,11,h),_p(6,11,h),_p(5,13,h),_p(6,13,h),_p(17,9,h),_p(18,9,h),_p(17,11,h),_p(18,11,h),_p(17,13,h),_p(18,13,h)));
        return string(abi.encodePacked(a,b,c,d));
    }
    function _bun(string memory h) private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(7,7,h),_p(8,7,h),_p(9,7,h),_p(10,7,h),_p(11,7,h),_p(12,7,h),_p(13,7,h),_p(14,7,h),_p(15,7,h),_p(16,7,h)));
        string memory b=string(abi.encodePacked(_p(7,8,h),_p(8,8,h),_p(9,8,h),_p(10,8,h),_p(11,8,h),_p(12,8,h),_p(13,8,h),_p(14,8,h),_p(15,8,h),_p(16,8,h)));
        string memory c=string(abi.encodePacked(_p(9,5,h),_p(10,5,h),_p(11,5,h),_p(12,5,h),_p(13,5,h),_p(14,5,h),_p(9,6,h),_p(10,6,h),_p(11,6,h),_p(12,6,h),_p(13,6,h),_p(14,6,h)));
        string memory d=string(abi.encodePacked(_p(10,4,h),_p(11,4,h),_p(12,4,h),_p(13,4,h),_p(11,3,h),_p(12,3,h)));
        return string(abi.encodePacked(a,b,c,d));
    }
    function _wild(string memory h) private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(7,7,h),_p(8,7,h),_p(9,7,h),_p(10,7,h),_p(11,7,h),_p(12,7,h),_p(13,7,h),_p(14,7,h),_p(15,7,h),_p(16,7,h)));
        string memory b=string(abi.encodePacked(_p(7,8,h),_p(8,8,h),_p(9,8,h),_p(10,8,h),_p(11,8,h),_p(12,8,h),_p(13,8,h),_p(14,8,h),_p(15,8,h),_p(16,8,h)));
        string memory c=string(abi.encodePacked(_p(5,8,h),_p(5,9,h),_p(5,10,h),_p(5,11,h),_p(18,8,h),_p(18,9,h),_p(18,10,h),_p(18,11,h)));
        string memory d=string(abi.encodePacked(_p(7,5,h),_p(8,4,h),_p(11,4,h),_p(12,4,h),_p(15,5,h),_p(6,6,h),_p(17,6,h)));
        return string(abi.encodePacked(a,b,c,d));
    }
    function _cap(string memory h) private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(5,7,h),_p(6,7,h),_p(7,7,h),_p(8,7,h),_p(9,7,h),_p(10,7,h),_p(11,7,h),_p(12,7,h),_p(13,7,h),_p(14,7,h),_p(15,7,h),_p(16,7,h),_p(17,7,h),_p(18,7,h)));
        string memory b=string(abi.encodePacked(_p(5,8,h),_p(6,8,h),_p(7,8,h),_p(8,8,h),_p(9,8,h),_p(10,8,h),_p(11,8,h),_p(12,8,h),_p(13,8,h),_p(14,8,h),_p(15,8,h),_p(16,8,h),_p(17,8,h),_p(18,8,h)));
        string memory c=string(abi.encodePacked(_p(6,6,h),_p(8,6,h),_p(10,6,h),_p(12,6,h),_p(14,6,h),_p(16,6,h),_p(8,5,h),_p(10,5,h),_p(12,5,h),_p(14,5,h),_p(4,9,h),_p(11,5,'#fff')));
        return string(abi.encodePacked(a,b,c));
    }
    function _headband(string memory h) private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(7,7,h),_p(8,7,h),_p(9,7,h),_p(10,7,h),_p(11,7,h),_p(12,7,h),_p(13,7,h),_p(14,7,h),_p(15,7,h),_p(16,7,h)));
        string memory b=string(abi.encodePacked(_p(7,8,h),_p(8,8,h),_p(9,8,h),_p(10,8,h),_p(11,8,h),_p(12,8,h),_p(13,8,h),_p(14,8,h),_p(15,8,h),_p(16,8,h)));
        string memory c=string(abi.encodePacked(_p(5,9,'#FF4500'),_p(7,9,'#FF4500'),_p(9,9,'#FF4500'),_p(11,9,'#FF4500'),_p(13,9,'#FF4500'),_p(15,9,'#FF4500'),_p(17,9,'#FF4500')));
        string memory d=string(abi.encodePacked(_p(5,11,h),_p(5,13,h),_p(5,15,h),_p(18,11,h),_p(18,13,h),_p(18,15,h)));
        return string(abi.encodePacked(a,b,c,d));
    }
    function _stringy(string memory h) private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(7,6,h),_p(8,6,h),_p(9,6,h),_p(10,6,h),_p(11,6,h),_p(12,6,h),_p(13,6,h),_p(14,6,h),_p(15,6,h),_p(16,6,h)));
        string memory b=string(abi.encodePacked(_p(7,7,h),_p(8,7,h),_p(9,7,h),_p(10,7,h),_p(11,7,h),_p(12,7,h),_p(13,7,h),_p(14,7,h),_p(15,7,h),_p(16,7,h)));
        string memory c=string(abi.encodePacked(_p(7,8,h),_p(8,8,h),_p(9,8,h),_p(10,8,h),_p(11,8,h),_p(12,8,h),_p(13,8,h),_p(14,8,h),_p(15,8,h),_p(16,8,h)));
        string memory d=string(abi.encodePacked(_p(6,9,h),_p(6,11,h),_p(6,13,h),_p(6,15,h),_p(6,17,h),_p(6,19,h),_p(17,9,h),_p(17,11,h),_p(17,13,h),_p(17,15,h),_p(17,17,h),_p(17,19,h)));
        return string(abi.encodePacked(a,b,c,d));
    }





    function _hc(uint256 id) private pure returns(string memory){
        uint256 i=_r(id,3)%10;
        if(i==0)return"#1a1a1a";if(i==1)return"#8B4513";if(i==2)return"#FFD700";
        if(i==3)return"#DC143C";if(i==4)return"#4169E1";if(i==5)return"#00CC44";
        if(i==6)return"#FF69B4";if(i==7)return"#888888";if(i==8)return"#ffffff";
        return"#FF4500";
    }
    function _r(uint256 id,uint256 s) private pure returns(uint256){return uint256(keccak256(abi.encodePacked(id,s)));}
    function _p(uint256 x,uint256 y,string memory c) private pure returns(string memory){
        return string(abi.encodePacked('<rect x="',_n(x*10),'" y="',_n(y*10),'" width="10" height="10" fill="',c,'"/>'));
    }
    function _n(uint256 v) private pure returns(string memory){
        if(v==0)return"0";
        if(v<10)return string(abi.encodePacked(bytes1(uint8(48+v))));
        if(v<100)return string(abi.encodePacked(bytes1(uint8(48+v/10)),bytes1(uint8(48+v%10))));
        if(v<1000)return string(abi.encodePacked(bytes1(uint8(48+v/100)),bytes1(uint8(48+v/10%10)),bytes1(uint8(48+v%10))));
        return string(abi.encodePacked(bytes1(uint8(48+v/1000)),bytes1(uint8(48+v/100%10)),bytes1(uint8(48+v/10%10)),bytes1(uint8(48+v%10))));
    }
}
