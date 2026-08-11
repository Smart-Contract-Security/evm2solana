// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title MatchTypes
/// @notice Shared enum + struct definitions for the match oracle and scorer.
library MatchTypes {
    /// @dev Lifecycle of one match. One-way; whitepaper §05.
    enum Phase {
        SCHEDULED,    // pre-match; no stats
        LIVE,         // kickoff happened
        PROVISIONAL,  // stats posted; dispute window open
        SETTLED       // window elapsed, no open dispute, scoreable
    }

    /// @dev The 18 tracked statistics. Indices line up with ScoringEngine's
    /// weight/polarity tables.
    enum Stat {
        MP,    //  0  minutes played      +0.05
        GLS,   //  1  goals               +3
        AST,   //  2  assists             +2
        SH,    //  3  shots               +0.5
        SOT,   //  4  shots on target     +1
        ATT,   //  5  passes attempted    +0.05
        CMP,   //  6  passes completed    +0.08
        CMP_P, //  7  pass completion %   +1
        TKL,   //  8  tackles             +1
        INT,   //  9  interceptions       +1
        CLR,   // 10  clearances          +0.7
        AER,   // 11  aerial duels won    +1
        SV,    // 12  saves               +1.5
        GA,    // 13  goals against       −3
        CS,    // 14  clean sheets        +5
        YC,    // 15  yellow cards        −2
        RC,    // 16  red cards           −5
        OG     // 17  own goals           −5
    }

    /// @dev One player's settled stat line for one match.
    struct PlayerLine {
        uint16 playerId;
        uint32[18] stats;  // indexed by Stat. Counts; ScoringEngine applies weights.
    }
}
