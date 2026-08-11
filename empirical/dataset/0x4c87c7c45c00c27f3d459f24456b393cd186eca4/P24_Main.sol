// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

//  ___  _  _   ____  _  _  _  _  _  _  ____
// (__ )| || | (  _ \| || || || \| || |/ ___)
//  (_ \| || |  ) __/| || || || .  || |\___ \
// (___/ \_  / (__)  |_||_||_||_|\_||_|(____/
//       /_/
//
//   24 PUNKS - 10,000 On-Chain Pixel Punks
//   24punks.xyz - Ethereum Mainnet

/// @title  24Punks
/// @notice 10,000 fully on-chain generative pixel punks on Ethereum
/// @author 24punks.xyz

interface I1 {
    function renderBg(uint256 id) external pure returns (string memory);
    function renderHair(uint256 id) external pure returns (string memory);
    function renderHat(uint256 id) external pure returns (string memory);
    function renderHalo(uint256 id) external pure returns (string memory);
    function renderHorns(uint256 id) external pure returns (string memory);
    function bgName(uint256 id) external pure returns (string memory);
    function hairName(uint256 id) external pure returns (string memory);
    function hatName(uint256 id) external pure returns (string memory);
}
interface I2 {
    function renderHead(uint256 id) external pure returns (string memory);
    function renderFace(uint256 id) external pure returns (string memory);
    function renderExtras(uint256 id) external pure returns (string memory);
    function renderNeck(uint256 id) external pure returns (string memory);
    function renderBody(uint256 id) external pure returns (string memory);
    function typeName(uint256 id) external pure returns (string memory);
    function skinName(uint256 id) external pure returns (string memory);
    function neckName(uint256 id) external pure returns (string memory);
    function shirtName(uint256 id) external pure returns (string memory);
}
interface I3 {
    function renderAcc(uint256 id) external pure returns (string memory);
    function renderBeard(uint256 id) external pure returns (string memory);
    function accName(uint256 id) external pure returns (string memory);
    function beardName(uint256 id) external pure returns (string memory);
}
interface I4 {
    function eyeName(uint256 id) external pure returns (string memory);
    function haloName(uint256 id) external pure returns (string memory);
    function hornsName(uint256 id) external pure returns (string memory);
}
contract Punks24 {
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed approved, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed op, bool approved);
    event Minted(address indexed to, uint256 indexed id);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event RoyaltyUpdated(uint256 oldBps, uint256 newBps);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    error SoldOut();
    error BadFunds();
    error BadQty();
    error NoToken();
    error NoAuth();
    error BadXfer();
    error AlreadyFreeMinted();
    error FreeSoldOut();
    error NotOwner();
    error ContractPaused();
    error InvalidRoyalty(uint256 provided, uint256 max);
    error ZeroAddress();

    string public constant VERSION = "1.0.0";
    uint256 public constant MAX_SUPPLY  = 10000;
    uint256 public constant FREE_SUPPLY = 8000;
    uint256 public constant MINT_PRICE  = 0.0001 ether;
    uint256 public constant RESERVE     = 100;

    address private _dev;
    address private _r1; address private _r2;
    address private _r3; address private _r4;
    uint256 private _totalMinted;
    uint256 private _totalFreeMinted;
    bool private _paused;
    uint256 private _royaltyBps = 500;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _approved;
    mapping(address => mapping(address => bool)) private _approvedAll;
    mapping(address => uint256) public freeMinted;

    constructor(address r1_, address r2_, address r3_, address r4_) {
        _dev=msg.sender; _r1=r1_; _r2=r2_; _r3=r3_; _r4=r4_;
        for(uint256 i; i<RESERVE;){ _mint(msg.sender); unchecked{++i;} }
    }
    modifier onlyDev() { if(msg.sender!=_dev) revert NotOwner(); _; }
    function freemint() external {
        if(_paused) revert ContractPaused();
        if(msg.sender != tx.origin) revert NoAuth();
        if(freeMinted[msg.sender] >= 2) revert AlreadyFreeMinted();
        if(_totalFreeMinted>=FREE_SUPPLY) revert FreeSoldOut();
        if(_totalMinted>=MAX_SUPPLY) revert SoldOut();
        freeMinted[msg.sender]++;
        unchecked{_totalFreeMinted++;}
        _mint(msg.sender);
    }
    function mint(uint256 qty) external payable {
        if(_paused) revert ContractPaused();
        if(qty==0||qty>20) revert BadQty();
        if(_totalMinted+qty>MAX_SUPPLY) revert SoldOut();
        if(msg.value<MINT_PRICE*qty) revert BadFunds();
        for(uint256 i;i<qty;){_mint(msg.sender);unchecked{++i;}}
        uint256 cost=MINT_PRICE*qty;
        if(msg.value>cost){
            (bool ok,)=payable(msg.sender).call{value:msg.value-cost}("");
            if(!ok) revert BadXfer();
        }
    }
    function _mint(address to) private {
        uint256 id=_totalMinted; _owners[id]=to;
        unchecked{_balances[to]++;_totalMinted++;}
        emit Transfer(address(0),to,id);
        emit Minted(to,id);
    }
    function totalSupply() public view returns(uint256){return _totalMinted;}
    function totalFreeMinted() public view returns(uint256){return _totalFreeMinted;}
    function freeRemaining() public view returns(uint256){return FREE_SUPPLY-_totalFreeMinted;}
    function paidRemaining() public view returns(uint256){return MAX_SUPPLY-_totalMinted;}
    function name() public pure returns(string memory){return"24Punks";}
    function symbol() public pure returns(string memory){return"PUNK";}
    function owner() public view returns(address){return _dev;}
    function isPaused() public view returns(bool){return _paused;}
    function tokenExists(uint256 id) public view returns(bool){return id<_totalMinted;}
    function ownerOf(uint256 id) public view returns(address o){
        if(id>=_totalMinted) revert NoToken();
        for(uint256 i=id;;){o=_owners[i];if(o!=address(0))return o;unchecked{--i;}}
    }
    function balanceOf(address a) public view returns(uint256){return _balances[a];}
    function getApproved(uint256 id) public view returns(address){if(id>=_totalMinted)revert NoToken();return _approved[id];}
    function isApprovedForAll(address a,address b) public view returns(bool){return _approvedAll[a][b];}
    function approve(address to,uint256 id) public {
        address o=ownerOf(id);
        if(msg.sender!=o&&!_approvedAll[o][msg.sender])revert NoAuth();
        _approved[id]=to;emit Approval(o,to,id);
    }
    function setApprovalForAll(address op,bool ok) public {
        _approvedAll[msg.sender][op]=ok;emit ApprovalForAll(msg.sender,op,ok);
    }
    function transferFrom(address f,address t,uint256 id) public{_xfer(f,t,id);}
    function safeTransferFrom(address f,address t,uint256 id) public{_xfer(f,t,id);}
    function safeTransferFrom(address f,address t,uint256 id,bytes calldata) public{_xfer(f,t,id);}
    function _xfer(address f,address t,uint256 id) private {
        if(ownerOf(id)!=f)revert BadXfer();
        if(msg.sender!=f&&!_approvedAll[f][msg.sender]&&_approved[id]!=msg.sender)revert NoAuth();
        delete _approved[id];unchecked{--_balances[f];++_balances[t];}
        _owners[id]=t;uint256 nx=id+1;
        if(nx<_totalMinted&&_owners[nx]==address(0))_owners[nx]=f;
        emit Transfer(f,t,id);
    }
    function setPaused(bool p) external onlyDev {
        _paused=p;
        if(p) emit Paused(msg.sender);
        else emit Unpaused(msg.sender);
    }
    function setRoyalty(uint256 bps) external onlyDev {
        if(bps>1000) revert InvalidRoyalty(bps,1000);
        emit RoyaltyUpdated(_royaltyBps,bps);
        _royaltyBps=bps;
    }
    function transferOwnership(address newOwner) external onlyDev {
        if(newOwner==address(0)) revert ZeroAddress();
        emit OwnershipTransferred(_dev,newOwner);
        _dev=newOwner;
    }
    function tokensOfOwner(address addr) public view returns(uint256[] memory){
        uint256 bal=_balances[addr];
        uint256[] memory tokens=new uint256[](bal);
        uint256 idx=0;
        for(uint256 i=0;i<_totalMinted&&idx<bal;i++){
            if(ownerOf(i)==addr){tokens[idx]=i;unchecked{idx++;}}
        }
        return tokens;
    }
    function contractURI() public pure returns(string memory){
        return 'data:application/json,{"name":"24Punks","description":"10,000 fully on-chain generative pixel punks on Ethereum. No IPFS. No servers.","external_link":"https://24punks.xyz","seller_fee_basis_points":500}';
    }
    function _buildSvg(uint256 id) private view returns(string memory){
        I1 r1=I1(_r1);I2 r2=I2(_r2);I3 r3=I3(_r3);
        string memory p1=string(abi.encodePacked('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" shape-rendering="crispEdges">',r1.renderBg(id),r1.renderHalo(id),r1.renderHorns(id)));
        string memory p2=string(abi.encodePacked(r2.renderBody(id),r2.renderNeck(id),r2.renderHead(id),r1.renderHair(id),r1.renderHat(id)));
        string memory p3=string(abi.encodePacked(r2.renderFace(id),r3.renderAcc(id),r3.renderBeard(id),r2.renderExtras(id),'</svg>'));
        return string(abi.encodePacked(p1,p2,p3));
    }
    function tokenURI(uint256 id) public view returns(string memory){
        if(id>=_totalMinted) revert NoToken();
        I2 r2=I2(_r2);I3 r3=I3(_r3);I4 r4=I4(_r4);I1 r1=I1(_r1);
        string memory svg=_buildSvg(id);
        string memory attrs=string(abi.encodePacked(
            '[{"trait_type":"Type","value":"',r2.typeName(id),
            '"},{"trait_type":"Skin","value":"',r2.skinName(id),
            '"},{"trait_type":"Background","value":"',r1.bgName(id),
            '"},{"trait_type":"Hair","value":"',r1.hairName(id),
            '"},{"trait_type":"Hat","value":"',r1.hatName(id),
            '"},{"trait_type":"Accessory","value":"',r3.accName(id),
            '"},{"trait_type":"Beard","value":"',r3.beardName(id),
            '"},{"trait_type":"Eye Color","value":"',r4.eyeName(id),
            '"},{"trait_type":"Neck","value":"',r2.neckName(id),
            '"},{"trait_type":"Shirt","value":"',r2.shirtName(id),
            '"},{"trait_type":"Halo","value":"',r4.haloName(id),
            '"},{"trait_type":"Horns","value":"',r4.hornsName(id),'"}]'
        ));
        string memory json=string(abi.encodePacked(
            '{"name":"24Punks #',_n(id),
            '","description":"10,000 fully on-chain generative pixel punks on Ethereum. No IPFS. No servers. Pure on-chain art.",',
            '"image":"data:image/svg+xml,',svg,
            '","attributes":',attrs,'}'
        ));
        return string(abi.encodePacked('data:application/json,',json));
    }
    function supportsInterface(bytes4 x) public pure returns(bool){
        return x==0x01ffc9a7||x==0x80ac58cd||x==0x5b5e139f||x==0x2a55205a;
    }
    function royaltyInfo(uint256,uint256 s) external view returns(address,uint256){
        return(_dev,s*_royaltyBps/10000);
    }
    function withdraw() external onlyDev {
        (bool ok,)=_dev.call{value:address(this).balance}("");
        if(!ok)revert BadXfer();
    }
    receive() external payable {}
    function _n(uint256 v) private pure returns(string memory){
        if(v==0)return"0";
        if(v<10)return string(abi.encodePacked(bytes1(uint8(48+v))));
        if(v<100)return string(abi.encodePacked(bytes1(uint8(48+v/10)),bytes1(uint8(48+v%10))));
        if(v<1000)return string(abi.encodePacked(bytes1(uint8(48+v/100)),bytes1(uint8(48+v/10%10)),bytes1(uint8(48+v%10))));
        if(v<10000)return string(abi.encodePacked(bytes1(uint8(48+v/1000)),bytes1(uint8(48+v/100%10)),bytes1(uint8(48+v/10%10)),bytes1(uint8(48+v%10))));
        return string(abi.encodePacked(bytes1(uint8(48+v/10000)),bytes1(uint8(48+v/1000%10)),bytes1(uint8(48+v/100%10)),bytes1(uint8(48+v/10%10)),bytes1(uint8(48+v%10))));
    }
}
