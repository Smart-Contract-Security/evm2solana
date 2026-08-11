// SPDX-License-Identifier: MPL-2.0
pragma solidity ^0.8.17;

import "../../../../openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../security/AuthorizationModule.sol";

/**
 * @title NAVModule
 * @dev Manages Net Asset Value (NAV) tracking per epoch (24-hour periods)
 */
abstract contract NAVModule is Initializable, AuthorizationModule {
    // Events
    event EpochTransition(uint256 previousEpoch, uint256 currentEpoch);
    event updatedNAV(
        uint256 indexed epoch,
        uint256 previousNAV,
        uint256 newNAV
    );

    // State variables
    uint256 public currentEpoch;
    uint256 public latestNAV; 
    uint256 private _currentEpochStartTimestamp;
    uint256 private constant _epochDuration = 86400;
    uint256 public constant NAVScalingFactor = 10_000; // 1e4 scaling factor for NAV values
    string public currencyNAV;

    // Mapping to store NAV for each epoch
    mapping(uint256 => uint256) internal _epochToNAV;

    /**
     * @dev Initializes the NAV module
     */

    function __NAVModule_init_unchained(
        string memory currency
    ) internal onlyInitializing {
        // Initialize first epoch
        _currentEpochStartTimestamp = (block.timestamp / 86400) * 86400 + 21600; // 06:00 UTC
        if (block.timestamp % 86400 < 21600) {
            _currentEpochStartTimestamp -= 86400;
        }
        currentEpoch = 0;
        currencyNAV = currency;
    }

    /**
     * @dev Sets the NAV for the current epoch and fills any missing previous epochs
     * @param NAVValue The NAV value to set (scaled by 1e4)
     */
    function setLatestNAV(uint256 NAVValue) public onlyRole(MINTER_ROLE) {
        _transitionEpoch();
        _updateNAV(currentEpoch, NAVValue);
    }

    /**
     * @dev Sets the NAV for a specific epoch
     * @param epoch The epoch to set the NAV for
     * @param NAVValue The NAV value to set (scaled by 1e4)
     */
    function setNAV(
        uint256 epoch,
        uint256 NAVValue
    ) external onlyRole(MINTER_ROLE) {
        require(epoch <= currentEpoch, "NAV: Cannot set future epoch");
        uint256 previousNAV = _epochToNAV[epoch];
        _epochToNAV[epoch] = NAVValue;
        emit updatedNAV(epoch, previousNAV, NAVValue);
    }

    /**
     * @dev Returns the NAV for a specific epoch
     * @param epoch The epoch to query
     * @return The NAV value for the specified epoch
     */
    function getNAV(uint256 epoch) public view returns (uint256) {
        return _epochToNAV[epoch];
    }

    /**
     * @dev Internal function to handle epoch transitions
     */
    function _transitionEpoch() internal {
        uint256 timeSinceEpochStart = block.timestamp -
            _currentEpochStartTimestamp;
        uint256 epochDifference = timeSinceEpochStart / _epochDuration;

        if (epochDifference > 0) {
            uint256 prevEpoch = currentEpoch;
            currentEpoch += epochDifference;
            _currentEpochStartTimestamp += epochDifference * _epochDuration;

            // Align to 06:00 UTC
            uint256 targetCutoff = (_currentEpochStartTimestamp / 86400) *
                86400 +
                21600;
            if (_currentEpochStartTimestamp % 86400 < 21600) {
                targetCutoff -= 86400;
            }
            _currentEpochStartTimestamp = targetCutoff;

            emit EpochTransition(prevEpoch, currentEpoch);
        }
    }

    function _updateNAV(uint256 epoch, uint256 NAVValue) internal {
        uint256 previousNAV = _epochToNAV[epoch];
        
        // Fill in missing NAV values for skipped epochs
        if (epoch > 0) {
            uint256 maxSteps = 15; // Maximum number of days to look back
            
            // Look back up to 15 epochs to find the last known NAV
            for (uint256 i = 1; i <= maxSteps && (epoch - i) > 0; i++) {
                uint256 checkEpoch = epoch - i;
                if (_epochToNAV[checkEpoch] > 0) {
                    break;
                }
                // Fill in the gap with the new NAV value
                _epochToNAV[checkEpoch] = NAVValue;
                emit updatedNAV(checkEpoch, 0, NAVValue);
            }
        }
        
        // Set the current epoch's NAV
        _epochToNAV[epoch] = NAVValue;
        emit updatedNAV(epoch, previousNAV, NAVValue);

        // Update latestNAV if we're setting the current epoch
        if (epoch == currentEpoch) {
            latestNAV = NAVValue;
        }
    }

    uint256[48] private __gap;
}
