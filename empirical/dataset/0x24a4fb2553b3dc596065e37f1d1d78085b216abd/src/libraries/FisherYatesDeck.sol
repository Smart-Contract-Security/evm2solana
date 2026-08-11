// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title FisherYatesDeck
/// @notice Lazy, gas-frugal Fisher-Yates shuffle for drawing distinct indices
///         from a fixed pool of `size` items without replacement. State lives in
///         a caller-owned `Deck` storage struct, so a season can hold one deck
///         per pool and draw from it as opens settle.
///
///         The permutation is materialised lazily: `swap[i]` stores `value + 1`
///         (so the default 0 means "still the identity, i.e. i"). Each draw maps
///         a uniform index into the shrinking live range [0, size - drawn) and
///         folds the tail element into the drawn slot, exactly like the classic
///         in-place shuffle but touching only the two slots involved.
library FisherYatesDeck {
    struct Deck {
        uint256 drawn; // how many items have been drawn so far
        mapping(uint256 => uint256) swap; // lazy permutation, 1-indexed (0 == identity)
    }

    /// @notice Draw the next index from a pool of `size` distinct items. `seed`
    ///         must be unpredictable (e.g. block randomness) — it selects which
    ///         live slot is taken. Reverts (division by zero) once the deck is
    ///         exhausted; callers cap opens at `size` so that can't happen.
    function draw(Deck storage d, uint256 size, bytes32 seed) internal returns (uint256 chosen) {
        uint256 poolSize = size - d.drawn;
        uint256 drawIndex = uint256(seed) % poolSize;

        uint256 storedAtDraw = d.swap[drawIndex];
        chosen = storedAtDraw == 0 ? drawIndex : storedAtDraw - 1;

        uint256 lastIndex = poolSize - 1;
        uint256 storedAtLast = d.swap[lastIndex];
        uint256 lastValue = storedAtLast == 0 ? lastIndex : storedAtLast - 1;

        d.swap[drawIndex] = lastValue + 1;
        d.drawn += 1;
    }

    /// @notice Undrawn slots left in a pool of `size`.
    function remaining(Deck storage d, uint256 size) internal view returns (uint256) {
        return size - d.drawn;
    }
}
