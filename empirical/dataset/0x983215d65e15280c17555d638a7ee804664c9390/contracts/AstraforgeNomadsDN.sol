// SPDX-License-Identifier: MIT

/*

    ASTRAFORGE NOMADS
    https://astraforgenomads.xyz
    https://x.com/astraforgeerc

*/

pragma solidity ^0.8.24;

import {DN404} from "./lib/DN404.sol";
import {DN404Pooled} from "./lib/DN404Pooled.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract AstraforgeNomadsDN is DN404Pooled, Ownable, ERC2981, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_NFT_SUPPLY = 5_000;
    uint256 public constant INITIAL_TOKEN_SUPPLY = MAX_NFT_SUPPLY * 1e18;

    string private _baseTokenURI;
    string private _contractMetadataURI;

    uint256 public feePerNFTAcc;

    mapping(address => uint256) public userFeeDebt;
    mapping(address => uint256) public pendingFee;
    address public yieldHook;

    uint256 public totalEthOwed;

    event BaseURIUpdated(string newBaseURI);
    event ContractURIUpdated(string newContractURI);
    event YieldHookSet(address indexed hook);
    event FeeDistributed(uint256 amount, uint256 newAccPerNFT);
    event FeeClaimed(address indexed user, uint256 amount);
    event StuckETHWithdrawn(address indexed to, uint256 amount);

    error UnauthorizedHook();
    error WithdrawFailed();
    error InvalidAddress();
    error InvalidRoyaltyBps();
    error RescueFailed();
    error NothingToWithdraw();

    constructor(
        address mirror,
        address royaltyReceiver,
        uint96 royaltyBps,
        string memory baseURI_,
        string memory contractURI_
    ) Ownable(msg.sender) {
        if (mirror == address(0) || royaltyReceiver == address(0)) revert InvalidAddress();
        if (royaltyBps > 10_000) revert InvalidRoyaltyBps();

        _baseTokenURI = baseURI_;
        _contractMetadataURI = contractURI_;

        _initializeDN404Pooled(INITIAL_TOKEN_SUPPLY, MAX_NFT_SUPPLY, msg.sender, mirror);

        _setDefaultRoyalty(royaltyReceiver, royaltyBps);
    }

    function name() public pure virtual override returns (string memory) {
        return "Astraforge Nomads";
    }

    function symbol() public pure virtual override returns (string memory) {
        return "NOMAD";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function _tokenURI(uint256 tokenId) internal view override returns (string memory) {
        return string.concat(_baseTokenURI, tokenId.toString(), ".json");
    }

    function contractURI() external view returns (string memory) {
        return _contractMetadataURI;
    }

    function _beforeSharesChange(address account) internal override {
        uint256 acc = feePerNFTAcc;
        uint256 debt = userFeeDebt[account];
        if (acc != debt) {
            uint256 shares = _dnOwned[account].length;
            if (shares != 0) pendingFee[account] += shares * (acc - debt);
            userFeeDebt[account] = acc;
        }
    }

    function distributeFee() external payable {
        if (msg.sender != yieldHook) revert UnauthorizedHook();

        uint256 outstanding = totalNFTSupply();
        if (outstanding == 0) {
            (bool refunded, ) = msg.sender.call{value: msg.value}("");
            if (!refunded) revert WithdrawFailed();
            return;
        }

        uint256 perNFT = msg.value / outstanding;
        feePerNFTAcc += perNFT;

        totalEthOwed += perNFT * outstanding;
        emit FeeDistributed(msg.value, feePerNFTAcc);
    }

    function claimFee() external nonReentrant {

        _beforeSharesChange(msg.sender);
        uint256 amount = pendingFee[msg.sender];
        if (amount == 0) return;

        pendingFee[msg.sender] = 0;
        totalEthOwed -= amount;

        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert WithdrawFailed();
        emit FeeClaimed(msg.sender, amount);
    }

    function withdrawPending() external nonReentrant {
        uint256 amount = pendingFee[msg.sender];
        if (amount == 0) return;
        pendingFee[msg.sender] = 0;
        totalEthOwed -= amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert WithdrawFailed();
        emit FeeClaimed(msg.sender, amount);
    }

    function stuckETH() public view returns (uint256) {
        uint256 bal = address(this).balance;
        uint256 owed = totalEthOwed;
        return bal > owed ? bal - owed : 0;
    }

    function withdrawStuckETH(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        uint256 surplus = stuckETH();
        if (surplus == 0) revert NothingToWithdraw();
        (bool ok, ) = to.call{value: surplus}("");
        if (!ok) revert WithdrawFailed();
        emit StuckETHWithdrawn(to, surplus);
    }

    function previewClaimable(address user) external view returns (uint256) {
        uint256 acc = feePerNFTAcc;
        uint256 debt = userFeeDebt[user];
        uint256 base = pendingFee[user];
        if (acc > debt) base += _dnOwned[user].length * (acc - debt);
        return base;
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    function setContractURI(string calldata newContractURI) external onlyOwner {
        _contractMetadataURI = newContractURI;
        emit ContractURIUpdated(newContractURI);
    }

    function setYieldHook(address hook) external onlyOwner {
        yieldHook = hook;
        emit YieldHookSet(hook);
    }

    function setDefaultRoyalty(address receiver, uint96 fee) external onlyOwner {
        if (receiver == address(0)) revert InvalidAddress();
        if (fee > 10_000) revert InvalidRoyaltyBps();
        _setDefaultRoyalty(receiver, fee);
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(this)) revert InvalidAddress();
        if (to == address(0)) revert InvalidAddress();
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        if (!(ok && (data.length == 0 || abi.decode(data, (bool))))) revert RescueFailed();
    }

    function supportsInterface(bytes4 id)
        public
        view
        virtual
        override(DN404, ERC2981)
        returns (bool)
    {
        return DN404.supportsInterface(id) || ERC2981.supportsInterface(id);
    }

    receive() external payable {}
}
