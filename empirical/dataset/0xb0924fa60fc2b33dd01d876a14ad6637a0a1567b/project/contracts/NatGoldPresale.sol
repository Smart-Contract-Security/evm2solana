// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract NatGoldPresale is Initializable, OwnableUpgradeable, UUPSUpgradeable {
  using SafeERC20 for IERC20;

  uint8 internal constant USDT_DECIMALS = 6;
  uint8 internal constant NAT_GOLD_DECIMALS = 18;
  uint256 internal constant TOKEN_SCALE = 10 ** NAT_GOLD_DECIMALS;
  uint256 internal constant BPS = 10000;

  Phase public phase;
  address public admin;
  address public kycSigner;
  address public custodianWallet;
  IERC20 public usdtToken;
  IERC20 public natGoldToken;

  uint256 public discountBps;
  uint256 public totalUsdtDeposited;
  Purchase[] public purchases;

  // Indexes into the "purchases" queue for each individual user.
  mapping(address => uint64[]) public userPurchases;
  mapping(address => SettledAmount) public userSettled;

  uint256 public priceNum;
  uint256 public priceDen;
  uint256 public discountedTokenSupply;
  uint256 public discountedTokenCapPerUser;
  uint256 public totalTokensOwed;
  uint256 public usdtAccumulated;

  uint64 private settleIndex;

  uint256[10] __gap;

  enum Phase {
    Purchase,
    Settle,
    AwaitingFunds,
    Claim
  }

  struct Purchase {
    address buyer;
    uint256 usdtAmount;
    // If "true" will refund any remaining USDT that cannot be used to buy discounted tokens.
    bool refundIfNoDiscount;
  }

  struct SettledAmount {
    uint256 discountedTokens;
    uint256 fullPriceTokens;
    uint256 refundAmountUsdt;
  }

  struct UserPurchases {
    uint256 totalUsdt;
    Purchase[] purchases;
  }

  struct Status {
    Phase phase;
    uint256 totalUsdtDeposited;
    uint256 discountedTokenSupply;
    uint256 priceNum;
    uint256 priceDen;
  }

  error Unauthorized();

  event PhaseChange(Phase phase);
  event UserPurchase(address indexed sender, uint256 usdtAmount, bool refundIfNoDiscount);
  event UserClaim(address indexed sender, uint256 discountedTokens, uint256 fullPriceTokens, uint256 refundAmountUsdt);
  event CustodianWalletUpdated(address indexed previousWallet, address indexed newWallet);

  constructor() {
    _disableInitializers();
  }

  function initialize(
    IERC20 usdt,
    IERC20 natGold,
    address signer,
    address admin_,
    address custodianWallet_,
    // In basis points: 0.01% == 1BPS, 90% = 9000
    // This is used as such: actual price * discounted price.
    // So if we want 10% discount, we need to set this to 9000.
    uint256 discount
  )external initializer {
    require(address(usdt) != address(0));
    require(address(natGold) != address(0));
    require(signer != address(0));
    require(admin_ != address(0));
    require(custodianWallet_ != address(0));
    require(discount < BPS);

    require(
      IERC20Metadata(address(usdt)).decimals() == USDT_DECIMALS,
      "expecting USDT token to have 6 decimals"
    );

    require(
      IERC20Metadata(address(natGold)).decimals() == NAT_GOLD_DECIMALS,
      "expecting NatGold token to have 18 decimals"
    );

    __Ownable_init(admin_);
    __UUPSUpgradeable_init();

    phase = Phase.Purchase;
    usdtToken = usdt;
    natGoldToken = natGold;
    kycSigner = signer;
    admin = admin_;
    custodianWallet = custodianWallet_;
    discountBps = discount;
  }

  function _authorizeUpgrade(address newImpl) view internal override onlyOwner { }

  modifier requireAdmin() {
    require(msg.sender == admin, Unauthorized());

    _;
  }

  function requireKyc(bytes calldata signature, bytes calldata payload) view internal {
    bytes32 digest = keccak256(payload);

    address recovered = ECDSA.recover(digest, signature);
    require(recovered == kycSigner, Unauthorized());

    (address user, uint256 expiresAt) = abi.decode(payload, (address, uint256));
    require(msg.sender == user, Unauthorized());
    require(block.timestamp < expiresAt, Unauthorized());
  }

  function purchase(
    uint256 usdtAmount,
    bool refundIfNoDiscount,
    bytes calldata signature,
    bytes calldata payload
  ) external {
    require(usdtAmount > 0, "Amount cannot be 0.");
    require(phase == Phase.Purchase, "Purchases are closed.");

    requireKyc(signature, payload);

    uint64 index = uint64(purchases.length);
    usdtToken.safeTransferFrom(msg.sender, address(this), usdtAmount);

    purchases.push(
      Purchase({
          buyer: msg.sender,
          usdtAmount: usdtAmount,
          refundIfNoDiscount: refundIfNoDiscount
      })
    );

    userPurchases[msg.sender].push(index);
    totalUsdtDeposited += usdtAmount;

    emit UserPurchase(msg.sender, usdtAmount, refundIfNoDiscount);
  }

  function transitionSettle(
    // Price scaled to USDT decimals (6).
    uint256 _priceNum,
    // Used to express more complex price ratios. Will probably always want to set to "1" in practice.
    uint256 _priceDen,
    // Total number of available discounted tokens for sale. In human-readable units.
    uint256 discountedTokens,
    // Maximum number of discounted tokens that can be purchased by a single user. In human-readable units.
    uint256 discountedTokenCap
  ) external requireAdmin {
    require(phase == Phase.Purchase, "Already settled.");
    require(_priceNum > 0, "Price cannot be 0.");
    require(_priceDen >= 1, "Price denominator cannot be less than 1.");

    phase = Phase.Settle;
    priceNum = _priceNum;
    priceDen = _priceDen * TOKEN_SCALE;
    discountedTokenSupply = discountedTokens * TOKEN_SCALE;
    discountedTokenCapPerUser = discountedTokenCap * TOKEN_SCALE;

    emit PhaseChange(phase);
  }

  function runCrank(uint8 crankRuns) external {
    require(phase == Phase.Settle, "Not in settle phase.");
    require(crankRuns > 0);

    uint64 runs = uint64(Math.min(purchases.length - uint256(settleIndex), uint256(crankRuns)));
    uint64 end = settleIndex + runs;

    while (settleIndex < end) {
      Purchase storage p = purchases[settleIndex];
      SettledAmount storage settled = userSettled[p.buyer];

      uint256 remainingUsdt = p.usdtAmount;
      uint256 discountedRemaining = settled.discountedTokens < discountedTokenCapPerUser ? discountedTokenCapPerUser - settled.discountedTokens : 0;
      discountedRemaining = Math.min(discountedTokenSupply, discountedRemaining);

      if (remainingUsdt > 0 && discountedRemaining > 0) {
        uint256 discPriceNum = priceNum * discountBps;
        uint256 discPriceDen = priceDen * BPS;

        uint256 availableTokens = Math.mulDiv(remainingUsdt, discPriceDen, discPriceNum);
        availableTokens = Math.min(availableTokens, discountedRemaining);

        if (availableTokens > 0) {
          uint256 usdtCost = Math.mulDiv(availableTokens, discPriceNum, discPriceDen, Math.Rounding.Ceil);

          // Using saturatingSub to avoid getting the crank stuck in case of a rounding error
          // although this never actually happens in the randomized testing simulation.
          remainingUsdt = Math.saturatingSub(remainingUsdt, usdtCost);

          settled.discountedTokens += availableTokens;
          totalTokensOwed += availableTokens;
          discountedTokenSupply -= availableTokens;
        }
      }

      if (remainingUsdt > 0 && !p.refundIfNoDiscount) {
        uint256 availableTokens = Math.mulDiv(remainingUsdt, priceDen, priceNum);

        if (availableTokens > 0) {
          uint256 usdtCost = Math.mulDiv(availableTokens, priceNum, priceDen, Math.Rounding.Ceil);

          // Using saturatingSub to avoid getting the crank stuck in case of a rounding error
          // although this never actually happens in the randomized testing simulation.
          remainingUsdt = Math.saturatingSub(remainingUsdt, usdtCost);

          settled.fullPriceTokens += availableTokens;
          totalTokensOwed += availableTokens;
        }
      }

      settled.refundAmountUsdt += remainingUsdt;
      usdtAccumulated += p.usdtAmount - remainingUsdt;

      settleIndex += 1;
    }

    if (settleIndex >= purchases.length) {
      phase = Phase.AwaitingFunds;
      emit PhaseChange(phase);
    }
  }

  function fund(address from) external requireAdmin {
    require(phase == Phase.AwaitingFunds, "Not awaiting funds.");

    uint256 balance = natGoldToken.balanceOf(address(this));
    uint256 needed = Math.saturatingSub(totalTokensOwed, balance);

    if (needed > 0) {
      natGoldToken.safeTransferFrom(from, address(this), needed);
    }

    phase = Phase.Claim;
    emit PhaseChange(phase);
  }

  function claim() external {
    _claim(msg.sender);
  }

  function claimFor(address user) external {
    _claim(user);
  }

  function _claim(address user) internal {
    require(phase == Phase.Claim, "Not in claim phase.");

    SettledAmount storage settled = userSettled[user];

    uint256 fullPriceTokens = settled.fullPriceTokens;
    uint256 discountedTokens = settled.discountedTokens;
    uint256 refundAmount = settled.refundAmountUsdt;

    uint256 totalOwed = discountedTokens + fullPriceTokens;

    settled.discountedTokens = 0;
    settled.fullPriceTokens = 0;
    settled.refundAmountUsdt = 0;

    if (totalOwed > 0) {
      natGoldToken.safeTransfer(user, totalOwed);
    }

    if (refundAmount > 0) {
      usdtToken.safeTransfer(user, refundAmount);
    }

    if (totalOwed + refundAmount > 0) {
      emit UserClaim(user, discountedTokens, fullPriceTokens, refundAmount);
    }
  }

  function updateCustodianWallet(address newCustodianWallet) external requireAdmin {
    require(newCustodianWallet != address(0), "Wallet cannot be 0.");

    address previousWallet = custodianWallet;
    custodianWallet = newCustodianWallet;
    emit CustodianWalletUpdated(previousWallet, newCustodianWallet);
  }

  function transferUsdt() external requireAdmin {
    require(phase == Phase.Claim, "Not in claim phase.");

    uint256 amount = usdtAccumulated;
    usdtAccumulated = 0;

    if (amount > 0) {
      usdtToken.safeTransfer(custodianWallet, amount);
    }
  }

  function status() public view returns (Status memory) {
    return Status({
      phase: phase,
      totalUsdtDeposited: totalUsdtDeposited,
      discountedTokenSupply: discountedTokenSupply,
      priceNum: priceNum,
      priceDen: priceDen
    });
  }

  function purchasesForUser(address user) public view returns (UserPurchases memory) {
    uint256 total = 0;
    uint64[] storage indices = userPurchases[user];
    Purchase[] memory result = new Purchase[](indices.length);

    for(uint32 i = 0; i < indices.length; i++) {
      Purchase storage p = purchases[indices[i]];
      total += p.usdtAmount;
      result[i] = p;
    }

    return UserPurchases({
      totalUsdt: total,
      purchases: result
    });
  }

  function settledAmount(address user) public view returns (SettledAmount memory) {
    return userSettled[user];
  }

  function tokensOwed() public view returns (uint256) {
    return totalTokensOwed;
  }
}
