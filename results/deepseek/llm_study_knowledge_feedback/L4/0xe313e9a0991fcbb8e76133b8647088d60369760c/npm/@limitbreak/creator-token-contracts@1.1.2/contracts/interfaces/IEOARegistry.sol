// SPDX-License-Identifier: MIT

import "solana";

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IEOARegistry is IERC165 {
    function isVerifiedEOA(address account) external view returns (bool);
}