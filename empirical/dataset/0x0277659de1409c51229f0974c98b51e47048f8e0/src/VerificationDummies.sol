// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

struct VerificationPoolKeyLike {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

contract VerifyDummyTokenShape {
    string public nameValue;
    string public symbolValue;
    address public initialRecipientValue;
    uint256 public initialSupplyValue;
    address public holderAccountingActivatorValue;
    bytes32 public rewardExcludedHash;
    bytes32 public protocolTransferExemptHash;
    bytes32 public multiplierHash;

    constructor(
        string memory name_,
        string memory symbol_,
        address initialRecipient,
        uint256 initialSupply,
        address holderAccountingActivator_,
        address[] memory rewardExcludedAddresses,
        address[] memory protocolTransferExemptAddresses,
        uint16[169] memory multiplierBpsByAgeBucket_
    ) {
        nameValue = name_;
        symbolValue = symbol_;
        initialRecipientValue = initialRecipient;
        initialSupplyValue = initialSupply;
        holderAccountingActivatorValue = holderAccountingActivator_;
        rewardExcludedHash = keccak256(abi.encode(rewardExcludedAddresses));
        protocolTransferExemptHash = keccak256(abi.encode(protocolTransferExemptAddresses));
        multiplierHash = keccak256(abi.encode(multiplierBpsByAgeBucket_));
    }
}

contract VerifyDummyMechanicShape {
    address public weth;
    address public hook;
    address public treasury;
    address public token;

    constructor(address weth_, address hook_, address treasury_, address token_) {
        weth = weth_;
        hook = hook_;
        treasury = treasury_;
        token = token_;
    }
}

contract VerifyDummyHookShape {
    address public poolManager;
    address public expectedCurrency0;
    address public expectedCurrency1;
    uint24 public lpFee;
    int24 public tickSpacing;
    address public bootstrapLiquidityPath;
    address public authorizedInitializer;
    address public wethCurrency;
    address public mechanic;
    bool public holderAccountingEnabled;

    constructor(
        address poolManager_,
        address expectedCurrency0_,
        address expectedCurrency1_,
        uint24 lpFee_,
        int24 tickSpacing_,
        address bootstrapLiquidityPath_,
        address authorizedInitializer_,
        address wethCurrency_,
        address mechanic_,
        bool holderAccountingEnabled_
    ) {
        poolManager = poolManager_;
        expectedCurrency0 = expectedCurrency0_;
        expectedCurrency1 = expectedCurrency1_;
        lpFee = lpFee_;
        tickSpacing = tickSpacing_;
        bootstrapLiquidityPath = bootstrapLiquidityPath_;
        authorizedInitializer = authorizedInitializer_;
        wethCurrency = wethCurrency_;
        mechanic = mechanic_;
        holderAccountingEnabled = holderAccountingEnabled_;
    }
}

contract VerifyDummyPresaleShape {
    address public manager;
    address public token;
    address public weth;
    address public hook;
    bytes32 public expectedKeyHash;
    uint256 public contributionAmount;
    uint256 public maxRaiseWeth;
    address public launchOperator;

    constructor(
        address manager_,
        address token_,
        address weth_,
        address hook_,
        VerificationPoolKeyLike memory expectedKey_,
        uint256 contributionAmount_,
        uint256 maxRaiseWeth_,
        address launchOperator_
    ) {
        manager = manager_;
        token = token_;
        weth = weth_;
        hook = hook_;
        expectedKeyHash = keccak256(abi.encode(expectedKey_));
        contributionAmount = contributionAmount_;
        maxRaiseWeth = maxRaiseWeth_;
        launchOperator = launchOperator_;
    }
}

