//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title LabelValidator
/// @notice Pure label-format validation for our names.
/// @dev Labels must be 3–12 characters, lowercase alphanumeric or hyphen,
///      with no leading/trailing/consecutive hyphens.
library LabelValidator {
  error InvalidLabel();

  /// @notice Returns whether `label` conforms to our naming rules.
  /// @param label The candidate label string (expected lowercase, no dots).
  function isValid(
    string calldata label
  ) internal pure returns (bool) {
    bytes calldata b = bytes(label);
    uint256 len = b.length;

    if (len < 3 || len > 12) return false;
    if (b[0] == 0x2d || b[len - 1] == 0x2d) return false;

    bool prevHyphen;
    for (uint256 i; i < len; ++i) {
      bytes1 c = b[i];
      bool isHyphen = c == 0x2d;

      // a-z: 0x61–0x7a, 0-9: 0x30–0x39, hyphen: 0x2d
      if (!(isHyphen || (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39))) return false;
      if (isHyphen && prevHyphen) return false;

      prevHyphen = isHyphen;
    }
    return true;
  }

  /// @notice Validates that `label` conforms to our naming rules.
  /// @dev Reverts with InvalidLabel() on any violation.
  /// @param label The candidate label string (expected lowercase, no dots).
  function validateLabel(
    string calldata label
  ) internal pure {
    require(isValid(label), InvalidLabel());
  }
}
