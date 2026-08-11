// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;










library Address {
    //insufficient balance
    error InsufficientBalance(uint256 available, uint256 required);
    //unable to send value, recipient may have reverted
    error SendingValueFail();
    //insufficient balance for call
    error InsufficientBalanceForCall(uint256 available, uint256 required);
    //call to non-contract
    error NonContractCall();

    function isContract(address account) internal view returns (bool) {
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            codehash := extcodehash(account)
        }
        return (codehash != accountHash && codehash != 0x0);
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        uint256 balance = address(this).balance;
        if (balance < amount) {
            revert InsufficientBalance(balance, amount);
        }

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success,) = recipient.call{ value: amount }("");
        if (!(success)) {
            revert SendingValueFail();
        }
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(address target, bytes memory data, string memory errorMessage)
        internal
        returns (bytes memory)
    {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value)
        internal
        returns (bytes memory)
    {
        return functionCallWithValue(
            target, data, value, "Address: low-level call with value failed"
        );
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        uint256 balance = address(this).balance;
        if (balance < value) {
            revert InsufficientBalanceForCall(balance, value);
        }
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(
        address target,
        bytes memory data,
        uint256 weiValue,
        string memory errorMessage
    ) private returns (bytes memory) {
        if (!(isContract(target))) {
            revert NonContractCall();
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}







interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint256 digits);
    function totalSupply() external view returns (uint256 supply);

    function balanceOf(address _owner) external view returns (uint256 balance);

    function transfer(address _to, uint256 _value) external returns (bool success);

    function transferFrom(address _from, address _to, uint256 _value)
        external
        returns (bool success);

    function approve(address _spender, uint256 _value) external returns (bool success);

    function allowance(address _owner, address _spender) external view returns (uint256 remaining);

    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}











library SafeERC20 {
    using Address for address;

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(
            token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Compatible with tokens that require the approval to be set to
     * 0 before setting it to a non-zero value.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeWithSelector(token.approve.selector, spender, value);

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, 0));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata =
            address(token).functionCall(data, "SafeERC20: low-level call failed");
        require(
            returndata.length == 0 || abi.decode(returndata, (bool)),
            "SafeERC20: ERC20 operation did not succeed"
        );
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silents catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We cannot use {Address-functionCall} here since this should return false
        // and not revert is the subcall reverts.

        (bool success, bytes memory returndata) = address(token).call(data);
        return success && (returndata.length == 0 || abi.decode(returndata, (bool)))
            && address(token).code.length > 0;
    }
}







contract MainnetActionsUtilAddresses {
    address internal constant DFS_REG_CONTROLLER_ADDR = 0xF8f8B3C98Cf2E63Df3041b73f80F362a4cf3A576;
    address internal constant REGISTRY_ADDR = 0x287778F121F134C66212FB16c9b53eC991D32f5b;
    address internal constant DFS_LOGGER_ADDR = 0xcE7a977Cac4a481bc84AC06b2Da0df614e621cf3;
    address internal constant SUB_STORAGE_ADDR = 0x1612fc28Ee0AB882eC99842Cde0Fc77ff0691e90;
    address internal constant PROXY_AUTH_ADDR = 0x149667b6FAe2c63D1B4317C716b0D0e4d3E2bD70;
    address internal constant LSV_PROXY_REGISTRY_ADDRESS =
        0xa8a3c86c4A2DcCf350E84D2b3c46BDeBc711C16e;
    address internal constant TRANSIENT_STORAGE = 0x2F7Ef2ea5E8c97B8687CA703A0e50Aa5a49B7eb2;
    address internal constant TRANSIENT_STORAGE_CANCUN = 0x0304E27cccE28bAB4d78C6cb7AfD4cd01c87c1e4;
}







contract ActionsUtilHelper is MainnetActionsUtilAddresses { }







contract MainnetAuthAddresses {
    address internal constant ADMIN_VAULT_ADDR = 0xCCf3d848e08b94478Ed8f46fFead3008faF581fD;
    address internal constant DSGUARD_FACTORY_ADDRESS = 0x5a15566417e6C1c9546523066500bDDBc53F88C7;
    address internal constant ADMIN_ADDR = 0x25eFA336886C74eA8E282ac466BdCd0199f85BB9; // USED IN ADMIN VAULT CONSTRUCTOR
    address internal constant PROXY_AUTH_ADDRESS = 0x149667b6FAe2c63D1B4317C716b0D0e4d3E2bD70;
    address internal constant MODULE_AUTH_ADDRESS = 0x7407974DDBF539e552F1d051e44573090912CC3D;
}







contract AuthHelper is MainnetAuthAddresses { }







interface IAdminVault {
    function owner() external view returns (address);
    function admin() external view returns (address);
    function changeOwner(address _owner) external;
    function changeAdmin(address _admin) external;
}











contract AdminAuth is AuthHelper {
    using SafeERC20 for IERC20;

    IAdminVault public constant adminVault = IAdminVault(ADMIN_VAULT_ADDR);

    error SenderNotOwner();
    error SenderNotAdmin();

    modifier onlyOwner() {
        if (adminVault.owner() != msg.sender) {
            revert SenderNotOwner();
        }
        _;
    }

    modifier onlyAdmin() {
        if (adminVault.admin() != msg.sender) {
            revert SenderNotAdmin();
        }
        _;
    }

    /// @notice withdraw stuck funds
    function withdrawStuckFunds(address _token, address _receiver, uint256 _amount)
        public
        onlyOwner
    {
        if (_token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            payable(_receiver).transfer(_amount);
        } else {
            IERC20(_token).safeTransfer(_receiver, _amount);
        }
    }
}







interface IDFSRegistry {
    function getAddr(bytes4 _id) external view returns (address);

    function addNewContract(bytes32 _id, address _contractAddr, uint256 _waitPeriod) external;

    function startContractChange(bytes32 _id, address _newContractAddr) external;

    function approveContractChange(bytes32 _id) external;

    function cancelContractChange(bytes32 _id) external;

    function changeWaitPeriod(bytes32 _id, uint256 _newWaitPeriod) external;
}







contract DefisaverLogger {
    event RecipeEvent(address indexed caller, string indexed logName);

    event ActionDirectEvent(address indexed caller, string indexed logName, bytes data);

    function logRecipeEvent(string memory _logName) public {
        emit RecipeEvent(msg.sender, _logName);
    }

    function logActionDirectEvent(string memory _logName, bytes memory _data) public {
        emit ActionDirectEvent(msg.sender, _logName, _data);
    }
}







interface IDSProxy {
    function execute(bytes memory _code, bytes memory _data)
        external
        payable
        returns (address, bytes32);

    function execute(address _target, bytes memory _data) external payable returns (bytes32);

    function setCache(address _cacheAddr) external payable returns (bool);

    function owner() external view returns (address);

    function guard() external view returns (address);
}







interface IDSProxyFactory {
    function isProxy(address _proxy) external view returns (bool);
    function build(address owner) external returns (IDSProxy proxy);
    function build() external returns (IDSProxy proxy);
}






interface IInstaList {
    struct AccountLink {
        address first;
        address last;
        uint64 count;
    }

    struct AccountList {
        address prev;
        address next;
    }

    struct UserLink {
        uint64 first;
        uint64 last;
        uint64 count;
    }

    struct UserList {
        uint64 prev;
        uint64 next;
    }

    function accountAddr(uint64 _id) external view returns (address);
    function accountID(address _addr) external view returns (uint64);
    function accountLink(uint64 _id) external view returns (AccountLink memory);
    function accountList(uint64 _id, address _user) external view returns (AccountList memory);
    function userLink(address _user) external view returns (UserLink memory);
    function userList(address _user, uint64 _id) external view returns (UserList memory);
}







interface ISafe {
    enum Operation {
        Call,
        DelegateCall
    }

    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation
    ) external returns (bool success);

    function checkSignatures(bytes32 dataHash, bytes memory data, bytes memory signatures)
        external
        view;

    function checkNSignatures(
        address executor,
        bytes32 dataHash,
        bytes memory, /* data */
        bytes memory signatures,
        uint256 requiredSignatures
    ) external view;

    function approveHash(bytes32 hashToApprove) external;

    function domainSeparator() external view returns (bytes32);

    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);

    function nonce() external view returns (uint256);

    function setFallbackHandler(address handler) external;

    function getOwners() external view returns (address[] memory);

    function isOwner(address owner) external view returns (bool);

    function getThreshold() external view returns (uint256);

    function enableModule(address module) external;

    function isModuleEnabled(address module) external view returns (bool);

    function disableModule(address prevModule, address module) external;

    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);
}







contract MainnetDSAProxyFactoryAddresses {
    address internal constant DSA_LIST_ADDR = 0x4c8a1BEb8a87765788946D6B19C6C6355194AbEb;
}







contract DSAProxyFactoryHelper is MainnetDSAProxyFactoryAddresses { }







contract MainnetProxyFactoryAddresses {
    address internal constant PROXY_FACTORY_ADDR = 0xA26e15C895EFc0616177B7c1e7270A4C7D51C997;
}







contract DSProxyFactoryHelper is MainnetProxyFactoryAddresses { }







contract MainnetSFProxyFactoryAddresses {
    address internal constant SF_PROXY_FACTORY_ADDR = 0xF7B75183A2829843dB06266c114297dfbFaeE2b6;
    address internal constant SF_PROXY_GUARD = 0xCe91349d2A4577BBd0fC91Fe6019600e047f2847;
    bytes32 internal constant SF_PROXY_CODEHASH =
        0x15b0c1a13812f0fce8291b8e7786ece58e0daab08d489cdfe2899fdac4f66045;
}







contract SFProxyFactoryHelper is MainnetSFProxyFactoryAddresses { }







enum WalletType {
    DSPROXY,
    SAFE,
    DSAPROXY,
    SFPROXY
}















contract SmartWalletUtils is DSProxyFactoryHelper, DSAProxyFactoryHelper, SFProxyFactoryHelper {
    /// @notice Determine the type of wallet an address represents
    function _getWalletType(address _wallet) internal view returns (WalletType) {
        if (_isDSProxy(_wallet)) {
            return WalletType.DSPROXY;
        }

        if (_isDSAProxy(_wallet)) {
            return WalletType.DSAPROXY;
        }

        if (_isSFProxy(_wallet)) {
            return WalletType.SFPROXY;
        }

        // Otherwise, we assume we are in context of Safe
        return WalletType.SAFE;
    }

    /// @notice Check if the wallet is a DSProxy
    function _isDSProxy(address _wallet) internal view returns (bool) {
        return IDSProxyFactory(PROXY_FACTORY_ADDR).isProxy(_wallet);
    }

    /// @notice Check if the wallet is a DSA Proxy Account
    function _isDSAProxy(address _wallet) internal view returns (bool) {
        return IInstaList(DSA_LIST_ADDR).accountID(_wallet) != 0;
    }

    /// @notice Check if the wallet is a Summerfi account
    function _isSFProxy(address _wallet) internal view returns (bool) {
        return _wallet.codehash == SF_PROXY_CODEHASH;
    }

    /// @notice Fetch the owner of the smart wallet or the wallet itself
    /// @dev For 1/1 Safe it returns the owner, otherwise it returns the wallet itself
    /// @dev Only supports Safe and DSProxy wallets because SFProxy and DSAProxy are not part of automation
    /// @param _wallet Address of the smart wallet
    /// @return Address of the owner or wallet
    function _fetchOwnerOrWallet(address _wallet) internal view returns (address) {
        if (_isDSProxy(_wallet)) return IDSProxy(_wallet).owner();

        // Otherwise, we assume we are in context of Safe
        address[] memory owners = ISafe(_wallet).getOwners();
        return owners.length == 1 ? owners[0] : _wallet;
    }
}











abstract contract ActionBase is AdminAuth, ActionsUtilHelper, SmartWalletUtils {
    event ActionEvent(string indexed logName, bytes data);

    IDFSRegistry public constant registry = IDFSRegistry(REGISTRY_ADDR);

    DefisaverLogger public constant logger = DefisaverLogger(DFS_LOGGER_ADDR);

    //Wrong sub index value
    error SubIndexValueError();
    //Wrong return index value
    error ReturnIndexValueError();

    /// @dev Subscription params index range [128, 255]
    uint8 public constant SUB_MIN_INDEX_VALUE = 128;
    uint8 public constant SUB_MAX_INDEX_VALUE = 255;

    /// @dev Return params index range [1, 127]
    uint8 public constant RETURN_MIN_INDEX_VALUE = 1;
    uint8 public constant RETURN_MAX_INDEX_VALUE = 127;

    /// @dev If the input value should not be replaced
    uint8 public constant NO_PARAM_MAPPING = 0;

    /// @dev We need to parse Flash loan actions in a different way
    enum ActionType {
        FL_ACTION,
        STANDARD_ACTION,
        FEE_ACTION,
        CHECK_ACTION,
        CUSTOM_ACTION
    }

    /// @notice Parses inputs and runs the implemented action through a user wallet
    /// @dev Is called by the RecipeExecutor chaining actions together
    /// @param _callData Array of input values each value encoded as bytes
    /// @param _subData Array of subscribed vales, replaces input values if specified
    /// @param _paramMapping Array that specifies how return and subscribed values are mapped in input
    /// @param _returnValues Returns values from actions before, which can be injected in inputs
    /// @return Returns a bytes32 value through user wallet, each actions implements what that value is
    function executeAction(
        bytes memory _callData,
        bytes32[] memory _subData,
        uint8[] memory _paramMapping,
        bytes32[] memory _returnValues
    ) public payable virtual returns (bytes32);

    /// @notice Parses inputs and runs the single implemented action through a user wallet
    /// @dev Used to save gas when executing a single action directly
    function executeActionDirect(bytes memory _callData) public payable virtual;

    /// @notice Returns the type of action we are implementing
    function actionType() public pure virtual returns (uint8);

    //////////////////////////// HELPER METHODS ////////////////////////////

    /// @notice Given an uint256 input, injects return/sub values if specified
    /// @param _param The original input value
    /// @param _mapType Indicated the type of the input in paramMapping
    /// @param _subData Array of subscription data we can replace the input value with
    /// @param _returnValues Array of subscription data we can replace the input value with
    function _parseParamUint(
        uint256 _param,
        uint8 _mapType,
        bytes32[] memory _subData,
        bytes32[] memory _returnValues
    ) internal pure returns (uint256) {
        if (isReplaceable(_mapType)) {
            if (isReturnInjection(_mapType)) {
                _param = uint256(_returnValues[getReturnIndex(_mapType)]);
            } else {
                _param = uint256(_subData[getSubIndex(_mapType)]);
            }
        }

        return _param;
    }

    /// @notice Given an addr input, injects return/sub values if specified
    /// @param _param The original input value
    /// @param _mapType Indicated the type of the input in paramMapping
    /// @param _subData Array of subscription data we can replace the input value with
    /// @param _returnValues Array of subscription data we can replace the input value with
    function _parseParamAddr(
        address _param,
        uint8 _mapType,
        bytes32[] memory _subData,
        bytes32[] memory _returnValues
    ) internal view returns (address) {
        if (isReplaceable(_mapType)) {
            if (isReturnInjection(_mapType)) {
                _param = address(bytes20((_returnValues[getReturnIndex(_mapType)])));
            } else {
                /// @dev The last two values are specially reserved for proxy addr and owner addr
                if (_mapType == 254) return address(this); // wallet address
                if (_mapType == 255) return _fetchOwnerOrWallet(address(this)); // owner if 1/1 wallet or the wallet itself

                _param = address(uint160(uint256(_subData[getSubIndex(_mapType)])));
            }
        }

        return _param;
    }

    /// @notice Given an bytes32 input, injects return/sub values if specified
    /// @param _param The original input value
    /// @param _mapType Indicated the type of the input in paramMapping
    /// @param _subData Array of subscription data we can replace the input value with
    /// @param _returnValues Array of subscription data we can replace the input value with
    function _parseParamABytes32(
        bytes32 _param,
        uint8 _mapType,
        bytes32[] memory _subData,
        bytes32[] memory _returnValues
    ) internal pure returns (bytes32) {
        if (isReplaceable(_mapType)) {
            if (isReturnInjection(_mapType)) {
                _param = (_returnValues[getReturnIndex(_mapType)]);
            } else {
                _param = _subData[getSubIndex(_mapType)];
            }
        }

        return _param;
    }

    /// @notice Checks if the paramMapping value indicated that we need to inject values
    /// @param _type Indicated the type of the input
    function isReplaceable(uint8 _type) internal pure returns (bool) {
        return _type != NO_PARAM_MAPPING;
    }

    /// @notice Checks if the paramMapping value is in the return value range
    /// @param _type Indicated the type of the input
    function isReturnInjection(uint8 _type) internal pure returns (bool) {
        return (_type >= RETURN_MIN_INDEX_VALUE) && (_type <= RETURN_MAX_INDEX_VALUE);
    }

    /// @notice Transforms the paramMapping value to the index in return array value
    /// @param _type Indicated the type of the input
    function getReturnIndex(uint8 _type) internal pure returns (uint8) {
        if (!(isReturnInjection(_type))) {
            revert SubIndexValueError();
        }

        return (_type - RETURN_MIN_INDEX_VALUE);
    }

    /// @notice Transforms the paramMapping value to the index in sub array value
    /// @param _type Indicated the type of the input
    function getSubIndex(uint8 _type) internal pure returns (uint8) {
        if (_type < SUB_MIN_INDEX_VALUE) {
            revert ReturnIndexValueError();
        }
        return (_type - SUB_MIN_INDEX_VALUE);
    }
}







abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    error ReentrantCall();

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        if (_status == _ENTERED) {
            revert ReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}







contract MainnetFLAddresses {
    address internal constant SOLO_MARGIN_ADDRESS = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DYDX_FL_FEE_FAUCET = 0x47f159C90850D5cE09E21F931d504536840f34b4;

    address internal constant AAVE_LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address internal constant AAVE_LENDING_POOL_ADDRESS_PROVIDER =
        0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;

    address internal constant AAVE_V3_LENDING_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant AAVE_V3_LENDING_POOL_ADDRESS_PROVIDER =
        0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    address internal constant SPARK_LENDING_POOL_ADDRESS_PROVIDER =
        0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE;
    address internal constant SPARK_LENDING_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;

    address internal constant DSS_FLASH_ADDR = 0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA;
    address internal constant DAI_ADDR = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant ST_ETH_ADDR = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant VAULT_ADDR = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant BALANCER_V3_VAULT_ADDR = 0xbA1333333333a1BA1108E8412f11850A5C319bA9;

    address internal constant GHO_ADDR = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address internal constant GHO_FLASH_MINTER_ADDR = 0xb639D208Bcf0589D54FaC24E655C79EC529762B8;
    address internal constant UNI_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address internal constant MORPHO_BLUE_ADDR = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    address internal constant CURVEUSD_FLASH_ADDR = 0xA7a4bb50AF91f90b6fEb3388E7f8286aF45b299B;
    address internal constant CURVEUSD_ADDR = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    address internal constant DFS_REGISTRY_ADDR = 0x287778F121F134C66212FB16c9b53eC991D32f5b;
}








contract StrategyModel {
    /// @dev Group of strategies bundled together so user can sub to multiple strategies at once
    /// @param creator Address of the user who created the bundle
    /// @param strategyIds Array of strategy ids stored in StrategyStorage
    struct StrategyBundle {
        address creator;
        uint64[] strategyIds;
    }

    /// @dev Template/Class which defines a Strategy
    /// @param name Name of the strategy useful for logging what strategy is executing
    /// @param creator Address of the user which created the strategy
    /// @param triggerIds Array of identifiers for trigger - bytes4(keccak256(TriggerName))
    /// @param actionIds Array of identifiers for actions - bytes4(keccak256(ActionName))
    /// @param paramMapping Describes how inputs to functions are piped from return/subbed values
    /// @param continuous If the action is repeated (continuos) or one time
    struct Strategy {
        string name;
        address creator;
        bytes4[] triggerIds;
        bytes4[] actionIds;
        uint8[][] paramMapping;
        bool continuous;
    }

    /// @dev List of actions grouped as a recipe
    /// @param name Name of the recipe useful for logging what recipe is executing
    /// @param callData Array of calldata inputs to each action
    /// @param subData Used only as part of strategy, subData injected from StrategySub.subData
    /// @param actionIds Array of identifiers for actions - bytes4(keccak256(ActionName))
    /// @param paramMapping Describes how inputs to functions are piped from return/subbed values
    struct Recipe {
        string name;
        bytes[] callData;
        bytes32[] subData;
        bytes4[] actionIds;
        uint8[][] paramMapping;
    }

    /// @dev Actual data of the sub we store on-chain
    /// @dev In order to save on gas we store a keccak256(StrategySub) and verify later on
    /// @param walletAddr Address of the users smart wallet/proxy
    /// @param isEnabled Toggle if the subscription is active
    /// @param strategySubHash Hash of the StrategySub data the user inputted
    struct StoredSubData {
        bytes20 walletAddr; // address but put in bytes20 for gas savings
        bool isEnabled;
        bytes32 strategySubHash;
    }

    /// @dev Instance of a strategy, user supplied data
    /// @param strategyOrBundleId Id of the strategy or bundle, depending on the isBundle bool
    /// @param isBundle If true the id points to bundle, if false points directly to strategyId
    /// @param triggerData User supplied data needed for checking trigger conditions
    /// @param subData User supplied data used in recipe
    struct StrategySub {
        uint64 strategyOrBundleId;
        bool isBundle;
        bytes[] triggerData;
        bytes32[] subData;
    }

    /// @dev Data needed when signing relay transaction
    /// @param maxTxCostInFeeToken Max tx cost user is willing to pay in fee token
    /// @param feeToken Address of the token user is willing to pay fee in
    /// @param tokenPriceInEth Price of the token in ETH
    /// @param deadline Deadline for the relay transaction to be executed
    /// @param shouldTakeFeeFromPosition Flag to indicate if fee should be taken from position, otherwise from EOA/wallet
    struct TxSaverSignedData {
        uint256 maxTxCostInFeeToken;
        address feeToken;
        uint256 tokenPriceInEth;
        uint256 deadline;
        bool shouldTakeFeeFromPosition;
    }
}







interface IRecipeExecutor {
    function executeRecipe(StrategyModel.Recipe calldata _currRecipe) external payable;

    function executeRecipeFromTxSaver(
        StrategyModel.Recipe calldata _currRecipe,
        StrategyModel.TxSaverSignedData calldata _txSaverData
    ) external payable;

    function executeRecipeFromStrategy(
        uint256 _subId,
        bytes[] calldata _actionCallData,
        bytes[] calldata _triggerCallData,
        uint256 _strategyIndex,
        StrategyModel.StrategySub memory _sub
    ) external payable;

    function executeActionsFromFL(StrategyModel.Recipe calldata _currRecipe, bytes32 _flAmount)
        external
        payable;
}







interface IInstaAccount {
    function isAuth(address _user) external view returns (bool);
    function enable(address _user) external;
    function disable(address _user) external;
    function version() external view returns (uint256);
}






interface IInstaAccountV2 is IInstaAccount {
    function cast(string[] memory, bytes[] memory, address) external payable returns (bytes32);

    function implementations() external view returns (address);
}






interface IAccountImplementation {
    function execute(address _target, bytes memory _data)
        external
        payable
        returns (bytes32 response);

    function send(address _target, bytes memory _data) external payable;

    function owner() external view returns (address owner);

    function guard() external view returns (address);
}






library DFSIds {
    bytes4 internal constant RECIPE_EXECUTOR = bytes4(keccak256("RecipeExecutor"));
    bytes4 internal constant STRATEGY_EXECUTOR = bytes4(keccak256("StrategyExecutorID")); // Abstract, so support both L1 and L2
    bytes4 internal constant TX_SAVER_EXECUTOR = bytes4(keccak256("TxSaverExecutor"));
    bytes4 internal constant BOT_AUTH = bytes4(keccak256("BotAuth"));
    bytes4 internal constant BOT_AUTH_FOR_TX_SAVER = bytes4(keccak256("BotAuthForTxSaver"));
    bytes4 internal constant KYBER_SCALING_HELPER = bytes4(keccak256("KyberInputScalingHelper"));
    bytes4 internal constant LLAMALEND_SWAPPER = bytes4(keccak256("LlamaLendSwapper"));
    bytes4 internal constant CURVE_SWAPPER = bytes4(keccak256("CurveUsdSwapper"));
    bytes4 internal constant CURVE_TRANSIENT_SWAPPER =
        bytes4(keccak256("CurveUsdSwapperTransient"));
    bytes4 internal constant SFPROXY_ENTRY_POINT = bytes4(keccak256("SFProxyEntryPoint"));
}









contract FLFeeFaucet {
    using SafeERC20 for IERC20;

    /// @notice Sends 2 wei to msg.sender
    /// @dev Anyone can call this method but it's not economically feasible to drain
    /// @param _tokenAddr Address of the token we want 2 wei
    function my2Wei(address _tokenAddr) public {
        IERC20(_tokenAddr).safeTransfer(msg.sender, 2);
    }
}


















contract FLHelper is MainnetFLAddresses, StrategyModel {
    uint16 internal constant AAVE_REFERRAL_CODE = 64;
    uint16 internal constant SPARK_REFERRAL_CODE = 64;
    string internal constant DEFISAVER_CONNECTOR_ID = "DEFI-SAVER-A";
    FLFeeFaucet internal constant flFeeFaucet = FLFeeFaucet(DYDX_FL_FEE_FAUCET);

    // Revert if execution fails when using safe wallet
    error SafeExecutionError();

    /// @notice Helper function to callback RecipeExecutor from FL contract
    /// @param _wallet Address of the wallet from which to callback RecipeExecutor/SFProxyEntryPoint
    /// @param _walletType Type of the wallet used
    /// @param _currRecipe Recipe to be executed
    /// @param _paybackAmount Payback flashloan amount including fees
    function _executeRecipe(
        address _wallet,
        WalletType _walletType,
        Recipe memory _currRecipe,
        uint256 _paybackAmount
    ) internal {
        address target = IDFSRegistry(DFS_REGISTRY_ADDR).getAddr(DFSIds.RECIPE_EXECUTOR);
        bytes memory data = abi.encodeWithSelector(
            IRecipeExecutor.executeActionsFromFL.selector, _currRecipe, _paybackAmount
        );

        if (_walletType == WalletType.DSPROXY) {
            IDSProxy(_wallet).execute{ value: address(this).balance }(target, data);

            return;
        }

        if (_walletType == WalletType.DSAPROXY) {
            string[] memory connectors = new string[](1);
            connectors[0] = DEFISAVER_CONNECTOR_ID;

            bytes[] memory connectorsData = new bytes[](1);
            connectorsData[0] = data;

            IInstaAccountV2(_wallet).cast{ value: address(this).balance }(
                connectors,
                connectorsData,
                address(this) // Only used for event logging, so here we will set it to the FL contract
            );

            return;
        }

        if (_walletType == WalletType.SFPROXY) {
            // SFProxy calls SFProxyEntryPoint that will delegate the call to RecipeExecutor
            address sfProxyEntryPoint =
                IDFSRegistry(DFS_REGISTRY_ADDR).getAddr(DFSIds.SFPROXY_ENTRY_POINT);

            IAccountImplementation(_wallet).execute{ value: address(this).balance }(
                sfProxyEntryPoint, data
            );

            return;
        }

        // Otherwise, we assume we are in context of Safe
        bool success = ISafe(_wallet)
            .execTransactionFromModule(
                target, address(this).balance, data, ISafe.Operation.DelegateCall
            );

        if (!success) {
            revert SafeExecutionError();
        }
    }
}






interface IFlashLoanBase {
    struct FlashLoanParams {
        address[] tokens;
        uint256[] amounts;
        uint256[] modes;
        address onBehalfOf;
        address flParamGetterAddr;
        bytes flParamGetterData;
        bytes recipeData;
    }
}







interface IFLParamGetter {
    function getFlashLoanParams(bytes memory _data)
        external
        view
        returns (address[] memory tokens, uint256[] memory amount, uint256[] memory modes);
}






interface IDebtToken {
    function approveDelegation(address delegatee, uint256 amount) external;
    function borrowAllowance(address fromUser, address toUser) external view returns (uint256);
    function delegationWithSig(address, address, uint256, uint256, uint8, bytes32, bytes32) external;
    function nonces(address) external view returns (uint256);
    function name() external view returns (string memory);
}






library DataTypes {
    /// @dev Legacy reserve data
    struct ReserveData {
        //stores the reserve configuration
        ReserveConfigurationMap configuration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        // DEPRECATED on v3.2.0
        uint128 currentStableBorrowRate;
        //timestamp of last update
        uint40 lastUpdateTimestamp;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint16 id;
        //aToken address
        address aTokenAddress;
        // DEPRECATED on v3.2.0
        address stableDebtTokenAddress;
        //variableDebtToken address
        address variableDebtTokenAddress;
        // DEPRECATED on v3.4.0, should use the `RESERVE_INTEREST_RATE_STRATEGY` variable from the Pool contract
        address interestRateStrategyAddress;
        //the current treasury balance, scaled
        uint128 accruedToTreasury;
        // DEPRECATED on v3.4.0
        uint128 unbacked;
        // DEPRECATED on v3.7.0
        uint128 isolationModeTotalDebt;
    }

    struct ReserveConfigurationMap {
        //bit 0-15: LTV
        //bit 16-31: Liq. threshold
        //bit 32-47: Liq. bonus
        //bit 48-55: Decimals
        //bit 56: reserve is active
        //bit 57: reserve is frozen
        //bit 58: borrowing is enabled
        //bit 59: DEPRECATED: stable rate borrowing enabled
        //bit 60: asset is paused
        //bit 61: DEPRECATED: borrowing in isolation mode is enabled
        //bit 62: DEPRECATED: siloed borrowing enabled
        //bit 63: flashloaning enabled
        //bit 64-79: reserve factor
        //bit 80-115: borrow cap in whole tokens, borrowCap == 0 => no cap
        //bit 116-151: supply cap in whole tokens, supplyCap == 0 => no cap
        //bit 152-167: liquidation protocol fee
        //bit 168-175: DEPRECATED: eMode category
        //bit 176-211: DEPRECATED: unbacked mint cap
        //bit 212-251: DEPRECATED: debt ceiling for isolation mode with (ReserveConfiguration::DEBT_CEILING_DECIMALS) decimals
        //bit 252: DEPRECATED: virtual accounting is enabled for the reserve
        //bit 253-255 unused
        uint256 data;
    }

    struct UserConfigurationMap {
        /**
         * @dev Bitmap of the users collaterals and borrows. It is divided in pairs of bits, one pair per asset.
         * The first bit indicates if an asset is used as collateral by the user, the second whether an
         * asset is borrowed by the user.
         */
        uint256 data;
    }

    // DEPRECATED: kept for backwards compatibility, might be removed in a future version
    struct EModeCategoryLegacy {
        // each eMode category has a custom ltv and liquidation threshold
        uint16 ltv;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        // DEPRECATED
        address priceSource;
        string label;
    }

    struct CollateralConfig {
        uint16 ltv;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
    }

    struct EModeCategoryNew {
        // each eMode category has a custom ltv and liquidation threshold
        uint16 ltv;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        uint128 collateralBitmap;
        bool isolated; // if true, only assets in collateralBitmap can be used as collateral, and all others will have ltv0 rules applying
        string label;
        uint128 borrowableBitmap;
        uint128 ltvzeroBitmap; // if true, the asset will be treated as ltv0 and ltv0 rules apply
    }

    enum InterestRateMode {
        NONE,
        _DEPRECATED,
        VARIABLE
    }

    struct CalculateInterestRatesParams {
        uint256 unbacked;
        uint256 liquidityAdded;
        uint256 liquidityTaken;
        uint256 totalDebt;
        uint256 reserveFactor;
        address reserve;
        // @notice DEPRECATED in 3.4, but kept for backwards compatibility
        bool usingVirtualBalance;
        uint256 virtualUnderlyingBalance;
    }
}






interface IPoolAddressesProvider {
    /**
     * @notice Returns the id of the Aave market to which this contract points to.
     * @return The market id
     *
     */
    function getMarketId() external view returns (string memory);

    /**
     * @notice Returns an address by its identifier.
     * @dev The returned address might be an EOA or a contract, potentially proxied
     * @dev It returns ZERO if there is no registered address with the given id
     * @param id The id
     * @return The address of the registered for the specified id
     */
    function getAddress(bytes32 id) external view returns (address);

    /**
     * @notice Returns the address of the Pool proxy.
     * @return The Pool proxy address
     *
     */
    function getPool() external view returns (address);

    /**
     * @notice Returns the address of the PoolConfigurator proxy.
     * @return The PoolConfigurator proxy address
     *
     */
    function getPoolConfigurator() external view returns (address);

    /**
     * @notice Returns the address of the price oracle.
     * @return The address of the PriceOracle
     */
    function getPriceOracle() external view returns (address);

    /**
     * @notice Returns the address of the ACL manager.
     * @return The address of the ACLManager
     */
    function getACLManager() external view returns (address);

    /**
     * @notice Returns the address of the ACL admin.
     * @return The address of the ACL admin
     */
    function getACLAdmin() external view returns (address);

    /**
     * @notice Returns the address of the price oracle sentinel.
     * @return The address of the PriceOracleSentinel
     */
    function getPriceOracleSentinel() external view returns (address);

    /**
     * @notice Returns the address of the data provider.
     * @return The address of the DataProvider
     */
    function getPoolDataProvider() external view returns (address);
}







interface IPoolV3 {
    /**
     * @notice Supplies an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User supplies 100 USDC and gets in return 100 aUSDC
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     *
     */
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    /**
     * @notice Supply with transfer approval of asset to be supplied done via permit function
     * see: https://eips.ethereum.org/EIPS/eip-2612 and https://eips.ethereum.org/EIPS/eip-713
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     * @param deadline The deadline timestamp that the permit is valid
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     * @param permitV The V parameter of ERC712 permit sig
     * @param permitR The R parameter of ERC712 permit sig
     * @param permitS The S parameter of ERC712 permit sig
     *
     */
    function supplyWithPermit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external;

    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to The address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     *
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    /**
     * @notice Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
     * already supplied enough collateral, or he was given enough allowance by a credit delegator on the
     * corresponding debt token (StableDebtToken or VariableDebtToken)
     * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
     *   and 100 stable/variable debt tokens, depending on the `interestRateMode`
     * @param asset The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param interestRateMode The interest rate mode at which the user wants to borrow: 1 is deprecated, 2 for Variable
     * @param referralCode The code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     * @param onBehalfOf The address of the user who will receive the debt. Should be the address of the borrower itself
     * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
     * if he has been given credit delegation allowance
     *
     */
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
     * - E.g. User repays 100 USDC, burning 100 variable/stable debt tokens of the `onBehalfOf` address
     * @param asset The address of the borrowed underlying asset previously borrowed
     * @param amount The amount to repay
     * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
     * @param interestRateMode The interest rate mode at of the debt the user wants to repay: 1 is deprecated, 2 for Variable
     * @param onBehalfOf The address of the user who will get his debt reduced/removed. Should be the address of the
     * user calling the function if he wants to reduce/remove his own debt, or the address of any other
     * other borrower whose debt should be removed
     * @return The final amount repaid
     *
     */
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
        external
        returns (uint256);

    /**
     * @notice Repay with transfer approval of asset to be repaid done via permit function
     * see: https://eips.ethereum.org/EIPS/eip-2612 and https://eips.ethereum.org/EIPS/eip-713
     * @param asset The address of the borrowed underlying asset previously borrowed
     * @param amount The amount to repay
     * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
     * @param interestRateMode The interest rate mode at of the debt the user wants to repay: 1 is deprecated, 2 for Variable
     * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
     * user calling the function if he wants to reduce/remove his own debt, or the address of any other
     * other borrower whose debt should be removed
     * @param deadline The deadline timestamp that the permit is valid
     * @param permitV The V parameter of ERC712 permit sig
     * @param permitR The R parameter of ERC712 permit sig
     * @param permitS The S parameter of ERC712 permit sig
     * @return The final amount repaid
     *
     */
    function repayWithPermit(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external returns (uint256);

    /**
     * @notice Repays a borrowed `amount` on a specific reserve using the reserve aTokens, burning the
     * equivalent debt tokens
     * - E.g. User repays 100 USDC using 100 aUSDC, burning 100 variable/stable debt tokens
     * @dev  Passing uint256.max as amount will clean up any residual aToken dust balance, if the user aToken
     * balance is not enough to cover the whole debt
     * @param asset The address of the borrowed underlying asset previously borrowed
     * @param amount The amount to repay
     * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
     * @param interestRateMode The interest rate mode at of the debt the user wants to repay: 1 is deprecated, 2 for Variable
     * @return The final amount repaid
     *
     */
    function repayWithATokens(address asset, uint256 amount, uint256 interestRateMode)
        external
        returns (uint256);

    /**
     * @notice Allows suppliers to enable/disable a specific supplied asset as collateral
     * @param asset The address of the underlying asset supplied
     * @param useAsCollateral True if the user wants to use the supply as collateral, false otherwise
     *
     */
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

    /**
     * @notice Allows smartcontracts to access the liquidity of the pool within one transaction,
     * as long as the amount taken plus a fee is returned.
     * @dev IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept
     * into consideration. For further details please visit https://developers.aave.com
     * @param receiverAddress The address of the contract receiving the funds, implementing IFlashLoanReceiver interface
     * @param assets The addresses of the assets being flash-borrowed
     * @param amounts The amounts of the assets being flash-borrowed
     * @param interestRateModes Types of the debt to open if the flash loan is not returned:
     *   0 -> Don't open any debt, just revert if funds can't be transferred from the receiver
     *   1 -> Open debt at stable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
     *   2 -> Open debt at variable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
     * @param onBehalfOf The address  that will receive the debt in the case of using on `modes` 1 or 2
     * @param params Variadic packed params to pass to the receiver as extra information
     * @param referralCode The code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     *
     */
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

    /**
     * @notice Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralBase The total collateral of the user in the base currency used by the price feed
     * @return totalDebtBase The total debt of the user in the base currency used by the price feed
     * @return availableBorrowsBase The borrowing power left of the user in the base currency used by the price feed
     * @return currentLiquidationThreshold The liquidation threshold of the user
     * @return ltv The loan to value of The user
     * @return healthFactor The current health factor of the user
     *
     */
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /**
     * @notice Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     *
     */
    function getConfiguration(address asset)
        external
        view
        returns (DataTypes.ReserveConfigurationMap memory);

    /**
     * @notice Returns the configuration of the user across all the reserves
     * @param user The user address
     * @return The configuration of the user
     *
     */
    function getUserConfiguration(address user)
        external
        view
        returns (DataTypes.UserConfigurationMap memory);

    /**
     * @notice Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state and configuration data of the reserve
     *
     */
    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory);

    /**
     * @notice Returns the list of the initialized reserves
     * @dev It does not include dropped reserves
     * @return The addresses of the reserves
     *
     */
    function getReservesList() external view returns (address[] memory);

    /**
     * @notice Returns the PoolAddressesProvider connected to this contract
     * @return The address of the PoolAddressesProvider
     *
     */
    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider);

    /**
     * @notice Returns the data of an eMode category
     * @param id The id of the category
     * @return The configuration data of the category
     */
    function getEModeCategoryData(uint8 id)
        external
        view
        returns (DataTypes.EModeCategoryLegacy memory);

    /**
     * @notice Allows a user to use the protocol in eMode
     * @param categoryId The id of the category
     */
    function setUserEMode(uint8 categoryId) external;

    /**
     * @notice Returns the eMode the user is using
     * @param user The address of the user
     * @return The eMode id
     */
    function getUserEMode(address user) external view returns (uint256);

    /**
     * @notice Returns the total fee on flash loans
     * @return The total fee on flashloans
     */
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);

    /**
     * @notice Returns the address of the underlying asset of a reserve by the reserve id as stored in the DataTypes.ReserveData struct
     * @param id The id of the reserve as stored in the DataTypes.ReserveData struct
     * @return The address of the reserve associated with id
     *
     */
    function getReserveAddressById(uint16 id) external view returns (address);

    /**
     * @notice Returns the label of an eMode category
     * @dev This function is deprecated and will be removed in a future version.
     * @custom:deprecated
     * @param id The id of the category
     * @return The label of the category
     */
    function getEModeCategoryLabel(uint8 id) external view returns (string memory);

    /**
     * @notice Returns the collateral config of an eMode category
     * @param id The id of the category
     * @return The ltv,lt,lb of the category
     */
    function getEModeCategoryCollateralConfig(uint8 id)
        external
        view
        returns (DataTypes.CollateralConfig memory);

    /**
     * @notice Returns the collateralBitmap of an eMode category
     * @param id The id of the category
     * @return The collateralBitmap of the category
     */
    function getEModeCategoryCollateralBitmap(uint8 id) external view returns (uint128);

    /**
     * @notice Returns the borrowableBitmap of an eMode category
     * @param id The id of the category
     * @return The borrowableBitmap of the category
     */
    function getEModeCategoryBorrowableBitmap(uint8 id) external view returns (uint128);

    /**
     * @notice Returns the ltvzero of an eMode category
     * @param id The id of the category
     * @return The ltvzeroBitmap of the category
     */
    function getEModeCategoryLtvzeroBitmap(uint8 id) external view returns (uint128);

    /**
     * @notice Returns the current deficit of a reserve.
     * @param asset The address of the underlying asset of the reserve
     * @return The current deficit of the reserve
     */
    function getReserveDeficit(address asset) external view returns (uint256);

    /**
     * @notice Returns the aToken address of a reserve.
     * @param asset The address of the underlying asset of the reserve
     * @return The address of the aToken
     */
    function getReserveAToken(address asset) external view returns (address);

    /**
     * @notice Returns the variableDebtToken address of a reserve.
     * @param asset The address of the underlying asset of the reserve
     * @return The address of the variableDebtToken
     */
    function getReserveVariableDebtToken(address asset) external view returns (address);

    /**
     * @notice Returns the virtual underlying balance of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The reserve virtual underlying balance
     */
    function getVirtualUnderlyingBalance(address asset) external view returns (uint128);

    /**
     * @notice Returns the ReserveInterestRateStrategy connected to all the reserves
     * @return The address of the ReserveInterestRateStrategy contract
     */
    function RESERVE_INTEREST_RATE_STRATEGY() external view returns (address);

    /**
     * @notice Returns the isolated flag of an eMode category
     * @param id The id of the category
     * @return True if the eMode category is isolated
     */
    function getIsEModeCategoryIsolated(uint8 id) external view returns (bool);
}







interface IWETH {
    function allowance(address, address) external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function approve(address, uint256) external;

    function transfer(address, uint256) external returns (bool);

    function transferFrom(address, address, uint256) external returns (bool);

    function deposit() external payable;

    function withdraw(uint256) external;
}









library TokenUtils {
    using SafeERC20 for IERC20;

    address public constant WETH_ADDR = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ETH_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev Only approves the amount if allowance is lower than amount, does not decrease allowance
    function approveToken(address _tokenAddr, address _to, uint256 _amount) internal {
        if (_tokenAddr == ETH_ADDR) return;

        if (IERC20(_tokenAddr).allowance(address(this), _to) < _amount) {
            IERC20(_tokenAddr).safeApprove(_to, _amount);
        }
    }

    function pullTokensIfNeeded(address _token, address _from, uint256 _amount)
        internal
        returns (uint256)
    {
        // handle max uint amount
        if (_amount == type(uint256).max) {
            _amount = getBalance(_token, _from);
        }

        if (_from != address(0) && _from != address(this) && _token != ETH_ADDR && _amount != 0) {
            IERC20(_token).safeTransferFrom(_from, address(this), _amount);
        }

        return _amount;
    }

    function withdrawTokens(address _token, address _to, uint256 _amount)
        internal
        returns (uint256)
    {
        if (_amount == type(uint256).max) {
            _amount = getBalance(_token, address(this));
        }

        if (_to != address(0) && _to != address(this) && _amount != 0) {
            if (_token != ETH_ADDR) {
                IERC20(_token).safeTransfer(_to, _amount);
            } else {
                (bool success,) = _to.call{ value: _amount }("");
                require(success, "Eth send fail");
            }
        }

        return _amount;
    }

    function depositWeth(uint256 _amount) internal {
        IWETH(WETH_ADDR).deposit{ value: _amount }();
    }

    function withdrawWeth(uint256 _amount) internal {
        IWETH(WETH_ADDR).withdraw(_amount);
    }

    function getBalance(address _tokenAddr, address _acc) internal view returns (uint256) {
        if (_tokenAddr == ETH_ADDR) {
            return _acc.balance;
        } else {
            return IERC20(_tokenAddr).balanceOf(_acc);
        }
    }

    function getTokenDecimals(address _token) internal view returns (uint256) {
        if (_token == ETH_ADDR) return 18;

        return IERC20(_token).decimals();
    }
}




















contract FLAaveV3CarryDebt is ActionBase, ReentrancyGuard, FLHelper, IFlashLoanBase {
    using TokenUtils for address;

    uint256 private constant VARIABLE_RATE_MODE = 2;

    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/
    /// @notice Thrown when the parameters length is invalid.
    error InvalidParamsLength();
    /// @notice Thrown when the rate mode is invalid.
    error InvalidRateMode();
    /// @notice Thrown when the flash loan amount is zero.
    error ZeroFlashLoanAmount();
    /// @dev FL Initiator must be this contract
    error UntrustedInitiator();
    /// @dev Caller must be the relevant FL source address
    error UntrustedLender();
    /// @dev Caller must be the user's wallet address
    error UntrustedSender(address sender, address wallet);
    /// @dev Credit delegation allowance must be 0 after FL
    error CreditDelegationAllowanceLeftError(uint256 amountLeft);

    /*//////////////////////////////////////////////////////////////
                              PUBLIC
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc ActionBase
    function actionType() public pure override returns (uint8) {
        return uint8(ActionType.FL_ACTION);
    }

    // solhint-disable-next-line no-empty-blocks
    function executeActionDirect(bytes memory _callData) public payable override { }

    /// @inheritdoc ActionBase
    function executeAction(
        bytes memory _callData,
        bytes32[] memory,
        uint8[] memory,
        bytes32[] memory
    ) public payable override returns (bytes32) {
        FlashLoanParams memory params = parseInputs(_callData);

        if (params.flParamGetterAddr != address(0)) {
            (params.tokens, params.amounts, params.modes) = IFLParamGetter(params.flParamGetterAddr)
                .getFlashLoanParams(params.flParamGetterData);
        }

        _validateParams(params);

        // We want to borrow onBehalf of user's wallet address which we can get from the current context.
        (, address wallet) = abi.decode(params.recipeData, (Recipe, address));

        // Only the wallet encoded by RecipeExecutor may initiate the carry-debt flash loan.
        // This binds Aave's onBehalfOf address to the wallet that receives and executes the recipe.
        if (msg.sender != wallet) revert UntrustedSender(msg.sender, wallet);

        // Trigger flashloan. This will move execution to 'executeOperation' function.
        IPoolV3(AAVE_V3_LENDING_POOL)
            .flashLoan(
                address(this),
                params.tokens,
                params.amounts,
                params.modes,
                wallet,
                params.recipeData,
                AAVE_REFERRAL_CODE
            );

        // Once we are here, this means that we already executed all other actions in the recipe.
        // In that case, verify that there is no credit delegation allowance left on this contract.
        for (uint256 i = 0; i < params.tokens.length; ++i) {
            address token =
                IPoolV3(AAVE_V3_LENDING_POOL).getReserveVariableDebtToken(params.tokens[i]);
            uint256 allowance = IDebtToken(token).borrowAllowance(wallet, address(this));
            if (allowance > 0) revert CreditDelegationAllowanceLeftError(allowance);
        }

        // Emit event.
        emit ActionEvent(
            "FLAaveV3CarryDebt", abi.encode(params.tokens, params.amounts, params.modes, wallet)
        );

        // In practice, this value is not used and is overwritten in RecipeExecutor:executeActionsFromFL,
        // where the actual flash loan amount is set as the first return value,
        // which is then used by subsequent actions.
        return bytes32(params.amounts[0]);
    }

    /*//////////////////////////////////////////////////////////////
                              CALLBACK
    //////////////////////////////////////////////////////////////*/
    /// @notice Aave callback function that formats and calls back RecipeExecutor
    /// FLSource == AAVE_V3
    /// Can have fees = NO
    /// @dev FL amount is not returned, instead debt is carried into the position.
    function executeOperation(
        address[] memory _assets,
        uint256[] memory _amounts,
        uint256[] memory,
        /* _fees */
        address _initiator,
        bytes memory _params
    ) public nonReentrant returns (bool) {
        if (msg.sender != AAVE_V3_LENDING_POOL) revert UntrustedLender();
        if (_initiator != address(this)) revert UntrustedInitiator();

        (Recipe memory currRecipe, address wallet) = abi.decode(_params, (Recipe, address));

        // Send FL amounts to user wallet.
        for (uint256 i = 0; i < _assets.length; ++i) {
            _assets[i].withdrawTokens(wallet, _amounts[i]);
        }

        // DFS actions can return only one value that can be used by other actions,
        // so we limit the return value to the first flash loan amount.
        _executeRecipe(wallet, _getWalletType(wallet), currRecipe, _amounts[0]);

        // Note: We don't return the FL amount, instead debt is carried into the position.

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    function parseInputs(bytes memory _callData)
        public
        pure
        returns (FlashLoanParams memory params)
    {
        params = abi.decode(_callData, (FlashLoanParams));
    }

    function _validateParams(FlashLoanParams memory _params) internal pure {
        uint256 length = _params.tokens.length;
        if (length == 0 || length != _params.amounts.length || length != _params.modes.length) {
            revert InvalidParamsLength();
        }
        for (uint256 i = 0; i < length; ++i) {
            if (_params.modes[i] != VARIABLE_RATE_MODE) revert InvalidRateMode();
            if (_params.amounts[i] == 0) revert ZeroFlashLoanAmount();
        }
    }
}