import 'solana';

library Stakes {
    struct Staker {
        uint64 tokensStaked;
        uint64 tokensLocked;
        uint64 tokensLockedUntil;
    }

    function deposit(Stakes.Staker storage stake, uint64 _tokens) internal {
        stake.tokensStaked += _tokens;
    }

    function release(Stakes.Staker storage stake, uint64 _tokens) internal {
        stake.tokensStaked -= _tokens;
    }

    function lockTokens(
        Stakes.Staker storage stake,
        uint64 _tokens,
        uint64 _period
    ) internal {
        stake.tokensLocked += _tokens;
        stake.tokensLockedUntil = uint64(block.slot) + _period;
    }

    function unlockTokens(
        Stakes.Staker storage stake,
        uint64 _tokens
    ) internal {
        stake.tokensLocked -= _tokens;
        stake.tokensLockedUntil = 0;
    }

    function withdrawTokens(
        Stakes.Staker storage stake
    ) internal returns (uint64) {
        uint64 tokensToWithdraw = tokensWithdrawable(stake);

        if (tokensToWithdraw > 0) {
            unlockTokens(stake, tokensToWithdraw);
            release(stake, tokensToWithdraw);
        }

        return tokensToWithdraw;
    }

    function tokensAvailable(
        Stakes.Staker memory stake
    ) internal pure returns (uint64) {
        return stake.tokensStaked - stake.tokensLocked;
    }

    function tokensWithdrawable(
        Stakes.Staker memory stake
    ) internal view returns (uint64) {
        if (
            stake.tokensLockedUntil == 0 ||
            block.slot < stake.tokensLockedUntil
        ) {
            return 0;
        }
        return stake.tokensLocked;
    }
}