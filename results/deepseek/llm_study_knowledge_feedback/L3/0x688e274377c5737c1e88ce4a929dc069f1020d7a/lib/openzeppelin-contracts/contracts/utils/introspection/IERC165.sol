// SPDX-License-Identifier: MIT

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}