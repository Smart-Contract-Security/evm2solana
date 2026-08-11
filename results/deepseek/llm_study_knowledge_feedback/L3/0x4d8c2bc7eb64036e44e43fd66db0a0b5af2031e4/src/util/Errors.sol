import {AccountMeta, AccountInfo} from 'solana';

library Errors {
    // Solana does not support custom errors with revert messages yet.
    // We use simple revert() calls instead.
    function NotAuthorized() internal pure {
        revert();
    }
    function WrongPhase() internal pure {
        revert();
    }
    function ZeroAddress() internal pure {
        revert();
    }
    function ZeroAmount() internal pure {
        revert();
    }
    function AlreadyInitialised() internal pure {
        revert();
    }
    function InvalidRarity() internal pure {
        revert();
    }
    function InvalidStat() internal pure {
        revert();
    }
    function InvalidTraitIndex() internal pure {
        revert();
    }
    function PotentialOverflow() internal pure {
        revert();
    }
    function UnknownPlayer() internal pure {
        revert();
    }
    function CardDoesNotExist() internal pure {
        revert();
    }
    function PackTierUnknown() internal pure {
        revert();
    }
    function PackAlreadyOpened() internal pure {
        revert();
    }
    function CallbackOutOfOrder() internal pure {
        revert();
    }
    function InsufficientPayment() internal pure {
        revert();
    }
}