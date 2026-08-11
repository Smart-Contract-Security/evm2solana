//SPDX-License-Identifier: CC-BY-NC-ND-4.0

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address recipient, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint64 amount) external returns (bool);
}

interface ITermRepoToken is IERC20 {
    // ========================================================================
    // = State Variables ======================================================
    // ========================================================================
    /// @notice The number of purchase tokens redeemable
    function redemptionValue() external view returns (uint64);

    // ========================================================================
    // = Interface/API ========================================================
    // ========================================================================

    /// @notice Calculates the total USD redemption value of all outstanding TermRepoTokens
    /// @return totalRedemptionValue Total redemption value of TermRepoTokens in USD
    function totalRedemptionValue() external view returns (uint64);

    /// @notice Burns TermRepoTokens held by an account
    /// @notice Reverts if caller does not have BURNER_ROLE
    /// @param account Address of account holding TermRepoTokens to burn
    /// @param amount Amount of TermRepoTokens to burn without decimal factor
    function burn(address account, uint64 amount) external;

    /// @notice Burns TermRepoTokens held by an account and returns purchase redemption value of tokens burned
    /// @notice Reverts if caller does not have BURNER_ROLE
    /// @param account Address of account holding TermRepoTokens to burn
    /// @param amount Amount of TermRepoTokens to burn without decimal factor
    /// @return totalRedemptionValue Total redemption value of TermRepoTokens burned
    function burnAndReturnValue(
        address account,
        uint64 amount
    ) external returns (uint64);

    /// @notice Mints TermRepoTokens in an amount equal to caller specified target redemption amount
    /// @notice The redemptionValue is the amount of purchase tokens redeemable per unit of TermRepoToken
    /// @notice Reverts if caller does not have MINTER_ROLE
    /// @param account Address of account to mint TermRepoTokens to
    /// @param redemptionAmount The target redemption amount to mint in TermRepoTokens
    function mintRedemptionValue(
        address account,
        uint64 redemptionAmount
    ) external returns (uint64);

    /// @notice Mints an exact amount of TermRepoTokens to an account
    /// @notice Reverts if caller does not have MINTER_ROLE
    /// @param account Theaddress of account to mint TermRepoTokens
    /// @param numTokens         exact number of term repo tokens to mint
    function mintTokens(
        address account,
        uint64 numTokens
    ) external returns (uint64);

    /// @notice Decrements the mintExposureCap
    /// @notice Reverts if caller does not have MINTER_ROLE
    /// @param supplyMinted Number of Tokens Minted
    function decrementMintExposureCap(uint64 supplyMinted) external;
}