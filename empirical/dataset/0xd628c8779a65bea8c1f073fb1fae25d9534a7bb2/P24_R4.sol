// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

// 24Punks Renderer 4 — Trait Names only
contract Punks24R4 {
    function _r(uint256 id,uint256 s) private pure returns(uint256){return uint256(keccak256(abi.encodePacked(id,s)));}

    function typeName(uint256 id) external pure returns(string memory){
        uint256 i=_r(id,4)%6;
        if(i==0)return"Human";if(i==1)return"Zombie";if(i==2)return"Alien";
        if(i==3)return"Ape";if(i==4)return"Robot";return"Ghost";
    }
    function hairName(uint256 id) external pure returns(string memory){
        uint256 i=_r(id,2)%9;
        if(i==0)return"Mohawk";if(i==1)return"Spiky";if(i==2)return"Long";
        if(i==3)return"Bun";if(i==4)return"Wild";if(i==5)return"Bald";
        if(i==6)return"Cap";if(i==7)return"Headband";return"Stringy";
    }
    function hatName(uint256 id) external pure returns(string memory){
        uint256 hair=_r(id,2)%9;
        if(hair==0||hair==4)return"None";
        uint256 i=_r(id,10)%5;
        if(i==0)return"None";if(i==1)return"Top Hat";if(i==2)return"Crown";
        if(i==3)return"Cowboy Hat";return"Beanie";
    }
    function bgName(uint256 id) external pure returns(string memory){
        uint256 i=_r(id,1)%8;
        if(i==0)return"Steel Blue";if(i==1)return"Warm Grey";if(i==2)return"Cool Grey";
        if(i==3)return"Navy";if(i==4)return"Olive";if(i==5)return"Brown";
        if(i==6)return"Teal";return"Purple";
    }
    function accName(uint256 id) external pure returns(string memory){
        uint256 i=_r(id,7)%7;
        if(i==0)return"None";if(i==1)return"Shades";if(i==2)return"3D Glasses";
        if(i==3)return"VR Headset";if(i==4)return"Monocle";if(i==5)return"Eye Patch";
        return"Nerd Glasses";
    }
    function beardName(uint256 id) external pure returns(string memory){
        uint256 ti=_r(id,4)%6;
        if(ti==2||ti==4||ti==5)return"None";
        uint256 i=_r(id,8)%5;
        if(i==0)return"None";if(i==1)return"Goatee";if(i==2)return"Full Beard";
        if(i==3)return"Moustache";return"Stubble";
    }
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
    function eyeName(uint256 id) external pure returns(string memory){
        uint256 i=_r(id,6)%6;
        if(i==0)return"Blue";if(i==1)return"Green";if(i==2)return"Orange";
        if(i==3)return"Purple";if(i==4)return"Pink";return"Gold";
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
    function haloName(uint256 id) external pure returns(string memory){
        return _r(id,20)%20==0?"Yes":"No";
    }
    function hornsName(uint256 id) external pure returns(string memory){
        if(_r(id,20)%20==0)return"No";
        return _r(id,21)%15==0?"Yes":"No";
    }

    function renderHat(uint256 id) external pure returns (string memory) {
        uint256 hair=_r(id,2)%9;
        if(hair==0||hair==4) return "";
        uint256 t=_r(id,10)%5;
        if(t==0) return "";
        if(t==1) return _tophat();
        if(t==2) return _crown();
        if(t==3) return _cowboy();
        return _beanie(_hc(id));
    }
    function _tophat() private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(8,3,'#111'),_p(9,3,'#111'),_p(10,3,'#111'),_p(11,3,'#111'),_p(12,3,'#111'),_p(13,3,'#111'),_p(14,3,'#111'),_p(15,3,'#111')));
        string memory b=string(abi.encodePacked(_p(8,4,'#111'),_p(9,4,'#111'),_p(10,4,'#111'),_p(11,4,'#111'),_p(12,4,'#111'),_p(13,4,'#111'),_p(14,4,'#111'),_p(15,4,'#111')));
        string memory c=string(abi.encodePacked(_p(8,5,'#111'),_p(9,5,'#111'),_p(10,5,'#111'),_p(11,5,'#111'),_p(12,5,'#111'),_p(13,5,'#111'),_p(14,5,'#111'),_p(15,5,'#111')));
        string memory d=string(abi.encodePacked(_p(8,6,'#111'),_p(9,6,'#111'),_p(10,6,'#111'),_p(11,6,'#111'),_p(12,6,'#111'),_p(13,6,'#111'),_p(14,6,'#111'),_p(15,6,'#111')));
        string memory e=string(abi.encodePacked(_p(6,7,'#111'),_p(7,7,'#111'),_p(8,7,'#111'),_p(9,7,'#111'),_p(10,7,'#111'),_p(11,7,'#111'),_p(12,7,'#111'),_p(13,7,'#111'),_p(14,7,'#111'),_p(15,7,'#111'),_p(16,7,'#111'),_p(17,7,'#111')));
        string memory f=string(abi.encodePacked(_p(6,8,'#111'),_p(7,8,'#111'),_p(8,8,'#111'),_p(9,8,'#111'),_p(10,8,'#111'),_p(11,8,'#111'),_p(12,8,'#111'),_p(13,8,'#111'),_p(14,8,'#111'),_p(15,8,'#111'),_p(16,8,'#111'),_p(17,8,'#111')));
        return string(abi.encodePacked(a,b,c,d,e,f));
    }
    function _crown() private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(8,7,'#FFD700'),_p(9,7,'#FFD700'),_p(10,7,'#FFD700'),_p(11,7,'#FFD700'),_p(12,7,'#FFD700'),_p(13,7,'#FFD700'),_p(14,7,'#FFD700'),_p(15,7,'#FFD700')));
        string memory b=string(abi.encodePacked(_p(8,8,'#FFD700'),_p(9,8,'#FFD700'),_p(10,8,'#FFD700'),_p(11,8,'#FFD700'),_p(12,8,'#FFD700'),_p(13,8,'#FFD700'),_p(14,8,'#FFD700'),_p(15,8,'#FFD700')));
        string memory c=string(abi.encodePacked(_p(8,6,'#FFD700'),_p(9,5,'#FFD700'),_p(11,4,'#FFD700'),_p(12,4,'#FFD700'),_p(14,5,'#FFD700'),_p(15,6,'#FFD700'),_p(9,6,'#FF0000'),_p(12,5,'#0000FF'),_p(14,6,'#00FF00')));
        return string(abi.encodePacked(a,b,c));
    }
    function _cowboy() private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(9,5,'#8B4513'),_p(10,5,'#8B4513'),_p(11,5,'#8B4513'),_p(12,5,'#8B4513'),_p(13,5,'#8B4513'),_p(14,5,'#8B4513')));
        string memory b=string(abi.encodePacked(_p(8,6,'#8B4513'),_p(9,6,'#8B4513'),_p(10,6,'#8B4513'),_p(11,6,'#8B4513'),_p(12,6,'#8B4513'),_p(13,6,'#8B4513'),_p(14,6,'#8B4513'),_p(15,6,'#8B4513')));
        string memory c=string(abi.encodePacked(_p(8,7,'#A0522D'),_p(9,7,'#A0522D'),_p(10,7,'#A0522D'),_p(11,7,'#A0522D'),_p(12,7,'#A0522D'),_p(13,7,'#A0522D'),_p(14,7,'#A0522D'),_p(15,7,'#A0522D')));
        string memory d=string(abi.encodePacked(_p(8,8,'#8B4513'),_p(9,8,'#8B4513'),_p(10,8,'#8B4513'),_p(11,8,'#8B4513'),_p(12,8,'#8B4513'),_p(13,8,'#8B4513'),_p(14,8,'#8B4513'),_p(15,8,'#8B4513')));
        string memory e=string(abi.encodePacked(_p(5,9,'#8B4513'),_p(6,9,'#8B4513'),_p(7,9,'#8B4513'),_p(8,9,'#8B4513'),_p(9,9,'#8B4513'),_p(10,9,'#8B4513'),_p(11,9,'#8B4513'),_p(12,9,'#8B4513'),_p(13,9,'#8B4513'),_p(14,9,'#8B4513'),_p(15,9,'#8B4513'),_p(16,9,'#8B4513'),_p(17,9,'#8B4513'),_p(18,9,'#8B4513')));
        return string(abi.encodePacked(a,b,c,d,e));
    }
    function _beanie(string memory h) private pure returns(string memory){
        string memory a=string(abi.encodePacked(_p(7,5,h),_p(8,5,h),_p(9,5,h),_p(10,5,h),_p(11,5,h),_p(12,5,h),_p(13,5,h),_p(14,5,h),_p(15,5,h),_p(16,5,h)));
        string memory b=string(abi.encodePacked(_p(7,6,h),_p(8,6,h),_p(9,6,h),_p(10,6,h),_p(11,6,h),_p(12,6,h),_p(13,6,h),_p(14,6,h),_p(15,6,h),_p(16,6,h)));
        string memory c=string(abi.encodePacked(_p(7,7,h),_p(8,7,h),_p(9,7,h),_p(10,7,h),_p(11,7,h),_p(12,7,h),_p(13,7,h),_p(14,7,h),_p(15,7,h),_p(16,7,h)));
        string memory d=string(abi.encodePacked(_p(7,8,h),_p(8,8,h),_p(9,8,h),_p(10,8,h),_p(11,8,h),_p(12,8,h),_p(13,8,h),_p(14,8,h),_p(15,8,h),_p(16,8,h)));
        string memory e=string(abi.encodePacked(_p(6,9,'#CC2222'),_p(7,9,'#CC2222'),_p(8,9,'#CC2222'),_p(9,9,'#CC2222'),_p(10,9,'#CC2222'),_p(11,9,'#CC2222'),_p(12,9,'#CC2222'),_p(13,9,'#CC2222'),_p(14,9,'#CC2222'),_p(15,9,'#CC2222'),_p(16,9,'#CC2222'),_p(17,9,'#CC2222')));
        return string(abi.encodePacked(a,b,c,d,e));
    }
    function _hc(uint256 id) private pure returns(string memory){
        uint256 i=_r(id,3)%10;
        if(i==0)return"#1a1a1a";if(i==1)return"#8B4513";if(i==2)return"#FFD700";
        if(i==3)return"#DC143C";if(i==4)return"#4169E1";if(i==5)return"#00CC44";
        if(i==6)return"#FF69B4";if(i==7)return"#888888";if(i==8)return"#ffffff";
        return"#FF4500";
    }

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