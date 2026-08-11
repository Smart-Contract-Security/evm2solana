// SPDX-License-Identifier: NO LICENSE

import 'solana';

interface IWoolfGen2 {
    function mint(address recipient) external;
    function migrate(address[] calldata _recipient, uint256[] calldata _tokenIds) external;
    function currentId() external view returns (uint64);
}