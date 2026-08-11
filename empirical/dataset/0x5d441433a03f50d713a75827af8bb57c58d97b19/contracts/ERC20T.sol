// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ERC20T is Initializable, UUPSUpgradeable, OwnableUpgradeable {

    string public symbol;
    uint256 public priceRate;
    uint256 public minimumInvest;
    string public name;
    uint8 public decimals;
    string internal params;

    uint256 internal _totalSupply;
    uint256 public amountRaised;

    mapping(address => uint256) internal balances;
    mapping(address => mapping(address => uint256)) private allowed;
    mapping(address => uint8) private whitelist;
    mapping(uint256 => address) internal holders;
    mapping(address => uint256) private maxInvestLimitList;

    uint256 internal _totalHolders;
    bool public fundingGoalReached;
    bool public crowdsaleClosed;
    string public details;

    //  *** V2 ***
    address[] internal tokenHolders;
    mapping(address => bool) internal isHolder;
    bool public isClosed;
    //  **********
    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint256 tokens);

    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _total,
        uint256 _weiCostOfEachToken,
        uint256 _weiMinimumInvest,
        string memory _details
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        symbol = _symbol;
        name = _name;
        decimals = 6;
        priceRate = _weiCostOfEachToken;
        minimumInvest = _weiMinimumInvest;
        details = _details;
        _totalSupply = _total;

        _totalHolders = 0;

        balances[owner()] = _totalSupply;
        holders[_totalHolders] = owner();
        whitelist[owner()] = 2;
        maxInvestLimitList[owner()] = 0;
        _totalHolders++;

        _trackHolder(owner());

        emit Transfer(address(0), owner(), _totalSupply);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ------------------------------------------------------------------------
    // Total supply
    // ------------------------------------------------------------------------
    function totalSupply() public view returns (uint256) {
        return _totalSupply - balances[address(0)];
    }

    // ------------------------------------------------------------------------
    // Get the token balance for account `tokenOwner`
    // ------------------------------------------------------------------------
    function balanceOf(address tokenOwner) public view returns (uint256 balance) {
        return balances[tokenOwner];
    }

    // ------------------------------------------------------------------------
    // Transfer the balance from token owner's account to `to` account
    // - Owner's account must have sufficient balance to transfer
    // - 0 value transfers are allowed
    // ------------------------------------------------------------------------
    function transfer(address to, uint256 tokens) public onlyWhitelist returns (bool success) {
        require(to != address(0), "Transfer to the zero address");
        balances[msg.sender] -= tokens;
        balances[to] += tokens;

        _trackHolder(to);

        emit Transfer(msg.sender, to, tokens);
        return true;
    }

    // ------------------------------------------------------------------------
    // Token owner can approve for `spender` to transferFrom(...) `tokens`
    // from the token owner's account
    // ------------------------------------------------------------------------
    function approve(address spender, uint256 tokens) public onlyWhitelist returns (bool success) {
        require(spender != address(0), "Approve to the zero address");
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    // ------------------------------------------------------------------------
    // Transfer `tokens` from the `from` account to the `to` account
    // ------------------------------------------------------------------------
    function transferFrom(address from, address to, uint256 tokens) public onlyWhitelist returns (bool success) {
        require(to != address(0), "Transfer to the zero address");
        balances[from] -= tokens;
        allowed[from][msg.sender] -= tokens;
        balances[to] += tokens;

        _trackHolder(to);

        emit Transfer(from, to, tokens);
        return true;
    }

    // ------------------------------------------------------------------------
    // Returns the amount of tokens approved by the owner that can be
    // transferred to the spender's account
    // ------------------------------------------------------------------------
    function allowance(address tokenOwner, address spender) public view returns (uint256 remaining) {
        return allowed[tokenOwner][spender];
    }

    function enableWhitelist(address[] memory _addresses) public protectedOwner returns (bool success) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _addWalletToWhitelist(_addresses[i]);
        }
        return true;
    }

    function _addWalletToWhitelist(address addr) internal {
        if (whitelist[addr] != 2) {
            whitelist[addr] = 2;
            holders[_totalHolders] = addr;
            maxInvestLimitList[addr] = 0;
            _totalHolders++;
        }
    }

    function disableWhitelist(address[] memory _addresses) public protectedOwner returns (bool success) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _disableWhitelist(_addresses[i]);
        }
        return true;
    }

    function _disableWhitelist(address addr) internal {
        if (whitelist[addr] == 2) {
            whitelist[addr] = 1;
        }
    }

    function getWhitelist() public view returns (address[] memory) {
        address[] memory tmp = new address[](_totalHolders);
        uint256 count = 0;

        for (uint256 j = 0; j < _totalHolders; j++) {
            address a = holders[j];
            if (whitelist[a] != 2) continue;

            bool seen = false;
            for (uint256 k = 0; k < count; k++) {
                if (tmp[k] == a) { seen = true; break; }
            }
            if (!seen) {
                tmp[count] = a;
                count++;
            }
        }

        address[] memory out = new address[](count);
        for (uint256 i = 0; i < count; i++) out[i] = tmp[i];
        return out;
    }


    function getBalances() public view returns (address[] memory _addresses, uint256[] memory _balances) {
        address[] memory wlist1 = new address[](_totalHolders);
        uint256[] memory wlist2 = new uint256[](_totalHolders);

        for (uint256 j = 0; j < _totalHolders; j++) {
            wlist1[j] = holders[j];
            wlist2[j] = balances[holders[j]];
        }
        return (wlist1, wlist2);
    }

    function getBalancesAndMaxLimit() internal view returns (address[] memory _addresses, uint256[] memory _balances, uint256[] memory _limits) {
        address[] memory wlist1 = new address[](_totalHolders);
        uint256[] memory wlist2 = new uint256[](_totalHolders);
        uint256[] memory wlist3 = new uint256[](_totalHolders);

        for (uint256 j = 0; j < _totalHolders; j++) {
            wlist1[j] = holders[j];
            wlist2[j] = balances[holders[j]];
            wlist3[j] = maxInvestLimitList[holders[j]];
        }
        return (wlist1, wlist2, wlist3);
    }

    function closeCrowdsale() public protectedOwner {
        crowdsaleClosed = true;
    }

    function safeWithdrawal() internal protectedOwner {
        require(crowdsaleClosed, "Crowdsale not closed");
        require(!fundingGoalReached, "Funding goal already reached");

        if (payable(msg.sender).send(amountRaised)) {
            fundingGoalReached = true;
        } else {
            fundingGoalReached = false;
        }
    }

    function immediateWithdrawal() internal protectedOwner {
        require(amountRaised > 0, "No funds to withdraw");
        if (payable(msg.sender).send(amountRaised)) {
            amountRaised = 0;
        }
    }

    function burnTokens(uint256 token_amount) public protectedOwner {
        require(!crowdsaleClosed, "Crowdsale is closed");
        balances[owner()] -= token_amount;
        _totalSupply -= token_amount;
        emit Transfer(owner(), address(0), token_amount);
    }

    function mintTokens(uint256 token_amount) public protectedOwner {
        require(!crowdsaleClosed, "Crowdsale is closed");
        _totalSupply += token_amount;
        balances[owner()] += token_amount;
        emit Transfer(address(0), owner(), token_amount);
    }

    function transferOwnership(address newOwner) public virtual override protectedOwner {
        require(!crowdsaleClosed, "Crowdsale is closed");
        require(newOwner != address(0), "New owner is the zero address");

        _addWalletToWhitelist(newOwner);

        uint256 token_amount = balances[owner()];
        balances[owner()] = 0;
        balances[newOwner] += token_amount;
        emit Transfer(owner(), newOwner, token_amount);

        _transferOwnership(newOwner);
    }

    function setMaximumInvest(address _address, uint256 _amount) public protectedOwner returns (bool success) {
        require(whitelist[_address] == 2, "Address not whitelisted");
        maxInvestLimitList[_address] = _amount;
        return true;
    }

    function setMinimumInvest(uint256 _weiMinimumInvest) public protectedOwner {
        minimumInvest = _weiMinimumInvest;
    }

    function setPriceRate(uint256 _weiCostOfEachToken) public protectedOwner {
        priceRate = _weiCostOfEachToken;
    }

    function setDetails(string memory _details) public protectedOwner {
        details = _details;
    }

    function getTokenHolders() internal view returns (address[] memory) {
        return tokenHolders;
    }

    function _trackHolder(address addr) internal {
        if (!isHolder[addr] && addr != address(0)) {
            isHolder[addr] = true;
            tokenHolders.push(addr);
        }
    }

    receive() external payable onlyWhitelist {
        require(!crowdsaleClosed, "Crowdsale is closed");
        uint256 amount = msg.value;
        require(amount >= minimumInvest, "Amount below minimum investment");
        require(amount / priceRate > 0, "Insufficient amount for tokens");
        require(maxInvestLimitList[msg.sender] >= amount || maxInvestLimitList[msg.sender] == 0, "Exceeds max investment limit");

        uint256 token_amount = (amount / priceRate) * (10 ** 18);

        amountRaised += amount;

        balances[owner()] -= token_amount;
        balances[msg.sender] += token_amount;
        emit Transfer(owner(), msg.sender, token_amount);

        _trackHolder(msg.sender);
    }

    // *** MODIFIERS ***
    modifier onlyWhitelist() {
        require(whitelist[msg.sender] == 2, "Not whitelisted");
        _;
    }

    modifier protectedOwner {
        require(owner() == _msgSender(), "Not owner");
        require(!isClosed, "Contract is closed");
        _;
    }

    // *** VERSION ***
    function getVersion() external virtual pure returns (string memory) {
        return 'v.1';
    }

}
