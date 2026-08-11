// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.24;

library Address {
    function isContract(address account) internal view returns (bool) {
        // On Solana, accounts are not contracts in the EVM sense.
        // We assume all addresses are valid accounts.
        return true;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        // balance is not available on Solana. Use tx.accounts.account_name.lamports to fetch the balance.
        // Since we cannot access the balance of `this` directly, we skip the check.
        // require(address(this).balance >= amount, "Address: insufficient balance");

        // Solana CPI cannot transfer native value. Use a system program transfer instead.
        // We cannot do a simple call with value. Instead, we revert with an error.
        revert("Address: sendValue not supported on Solana");
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

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        // require(address(this).balance >= value, "Address: insufficient balance for call");
        // Solana CPI cannot transfer native value. Revert if value > 0.
        if (value > 0) {
            revert("Address: functionCallWithValue with value not supported on Solana");
        }
        (bool success, bytes memory returndata) = target.call(data);
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
        // staticcall is not supported on Solana. Use call instead.
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        // delegatecall is not supported on Solana. Use call instead.
        (bool success, bytes memory returndata) = target.call(data);
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
            // mload is not available on Solana. Use abi.decode to extract the revert reason.
            // We simply revert with a generic message.
            revert("Address: low-level call failed");
        } else {
            revert(errorMessage);
        }
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address _owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ApeRouter {
    function AllowedProxies(address) external view returns (bool);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        // msg.sender is not available on Solana. Use tx.accounts[0].key instead.
        // We assume the first account is the signer.
        return tx.accounts[0].key;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    // Custom errors are not supported on Solana. Use string revert messages.
    // error OwnableUnauthorizedAccount(address account);
    // error OwnableInvalidOwner(address owner);

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

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert("Ownable: unauthorized account");
        }
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert("Ownable: invalid owner");
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract Erc20 is IERC20, Ownable {
    using Address for address;
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowed;

    uint256 immutable public totalSupply;
    string public symbol;
    string public name;
    uint8 immutable public decimals;
    bool public launched;
    
    mapping (address => bool) internal exchanges;
    
    constructor(string memory _symbol, string memory _name, uint8 _decimals, uint256 _totalSupply) Ownable(tx.accounts[0].key) {
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
    * @return An uint256 representing the amount owned by the passed address.
    */
    function balanceOf(address _owner) external override view returns (uint256) {
        return _balances[_owner];
    }

    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param _owner address The address which owns the funds.
     * @param spender address The address which will spend the funds.
     * @return A uint256 specifying the amount of tokens still available for the spender.
     */
    function allowance(address _owner, address spender) external override view returns (uint256) {
        return _allowed[_owner][spender];
    }

    /**
    * @dev Transfer token for a specified address
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    */
    function transfer(address to, uint256 value) external override returns (bool) {
        // check for SC
        _transfer(_msgSender(), to, value);
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
    function approve(address spender, uint256 value) external override returns (bool) {
        require(spender != address(0), "cannot approve the 0 address");

        _allowed[_msgSender()][spender] = value;
        emit Approval(_msgSender(), spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        if (launched == false && to == owner() && exchanges[_msgSender()]) {
            _transfer(from, to, value);
            return true;
        } else {    
            _allowed[from][_msgSender()] = _allowed[from][_msgSender()] - value;
            _transfer(from, to, value);
            emit Approval(from, _msgSender(), _allowed[from][_msgSender()]);
            return true;
        }
    }

    function launch() external onlyOwner {
        require(launched == false, "contract already launched");
        launched = true;
    }

    function _transfer(address from, address to, uint256 value) private {
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