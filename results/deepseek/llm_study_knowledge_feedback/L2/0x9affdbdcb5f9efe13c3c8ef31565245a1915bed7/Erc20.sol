//SPDX-License-Identifier: UNLICENSED

/*
Created on Ape.Store
*/

import 'solana';

library Address {
    
    function isContract(address account) internal view returns (bool) {
        (bool success, bytes memory data) = account.call{accounts: [tx.accounts[account]]}(abi.encodeWithSignature("global:noop"));
        return success;
    }

    function sendValue(address payable recipient, uint64 amount) internal {
        AccountInfo memory info = tx.accounts[recipient];
        require(info.lamports >= amount, "Address: insufficient balance");

        info.lamports -= amount;
        AccountInfo memory recipientInfo = tx.accounts[recipient];
        recipientInfo.lamports += amount;
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint64 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        AccountInfo memory info = tx.accounts[target];
        require(info.lamports >= value, "Address: insufficient balance for call");
        (bool success, bytes memory returndata) = target.call{accounts: [tx.accounts[target]]}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: [tx.accounts[target]]}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        if (returndata.length > 0) {
            revert(errorMessage);
        } else {
            revert(errorMessage);
        }
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address who) external view returns (uint64);
    function allowance(address _owner, address spender) external view returns (uint64);
    function transfer(address to, uint64 value) external returns (bool);
    function approve(address spender, uint64 value) external returns (bool);
    function transferFrom(address from, address to, uint64 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
}

interface ApeRouter {
    function AllowedProxies(address) external view returns (bool);
}

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts[0].key;
    }

    function _msgData() internal view returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert("Ownable: invalid owner");
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function _checkOwner() internal view {
        if (owner() != _msgSender()) {
            revert("Ownable: unauthorized account");
        }
    }

    function renounceOwnership() public onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) {
            revert("Ownable: invalid owner");
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract Erc20 is IERC20, Ownable {
    using Address for address;
    mapping (address => uint64) internal _balances;
    mapping (address => mapping (address => uint64)) internal _allowed;

    uint64 immutable public totalSupply;
    string public symbol;
    string public name;
    uint8 immutable public decimals;
    bool public launched;
    
    mapping (address => bool) internal exchanges;
    
    constructor(string memory _symbol, string memory _name, uint8 _decimals, uint64 _totalSupply) Ownable(tx.accounts[0].key)   {
        symbol = _symbol;
        name = _name;
        decimals = _decimals;
        totalSupply = _totalSupply;
        _balances[owner()] += _totalSupply;
        exchanges[owner()] = true;
        emit Transfer(address(0), owner(), _totalSupply);
    }

    /**
    * @dev Gets the balance of the specified address.
    * @param _owner The address to query the balance of.
    * @return An uint64 representing the amount owned by the passed address.
    */
    function balanceOf(address _owner) external override view returns (uint64) {
        return _balances[_owner];
    }

    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param _owner address The address which owns the funds.
     * @param spender address The address which will spend the funds.
     * @return A uint64 specifying the amount of tokens still available for the spender.
     */
    function allowance(address _owner, address spender) external override view returns (uint64) {
        return _allowed[_owner][spender];
    }

    /**
    * @dev Transfer token for a specified address
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    */
    function transfer(address to, uint64 value) external override returns (bool) {
        // check for SC
        _transfer(tx.accounts[0].key, to, value);
        return true;
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     * Beware that changing an allowance with this method brings the risk that someone may use both the old
     * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
     * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    function approve(address spender, uint64 value) external override returns (bool) {
        require(spender != address(0), "cannot approve the 0 address");

        _allowed[tx.accounts[0].key][spender] = value;
        emit Approval(tx.accounts[0].key, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint64 value) external override returns (bool) {
        if (launched == false && to == owner() && exchanges[tx.accounts[0].key]) {
            _transfer(from, to, value);
            return true;
        } else {    
            _allowed[from][tx.accounts[0].key] = _allowed[from][tx.accounts[0].key] - value;
            _transfer(from, to, value);
            emit Approval(from, tx.accounts[0].key, _allowed[from][tx.accounts[0].key]);
            return true;
        }
    }

    function launch() external onlyOwner {
        require(launched == false, "contract already launched");
        launched = true;
    }

    function _transfer(address from, address to, uint64 value) private {
        require(from != to, "you cannot transfer to yourself");
        require(_transferAllowed(from, to), "This token is not launched and cannot be listed on dexes yet.");
        _balances[from] -= value;
        _balances[to] += value;
        emit Transfer(from, to, value);
    }

    function _transferAllowed(address from, address to) private view returns (bool) {
      if (launched) return true;
      if (from == owner() || to == owner()) return true;
      if (from.isContract() || to.isContract()) return true;
      return true;
    }
}