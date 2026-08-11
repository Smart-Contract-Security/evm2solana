// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {IBlupetsDescriptor} from "./IBlupetsDescriptor.sol";

contract BlupetsDescriptor is Ownable, IBlupetsDescriptor {
    using Strings for uint256;

    uint8 public constant LINEAGE_ORIGIN = 36;

    struct Entry {
        string name;
        string key;
        bool exists;
    }

    mapping(uint8 => Entry) private _lineages;
    mapping(uint8 => Entry) private _vibes;
    mapping(uint256 => Entry) private _forms;

    event LineageSet(uint8 indexed lineage, string name, string key);
    event FormSet(uint8 indexed stage, uint8 indexed lineage, uint8 indexed form, string name, string artKey);
    event VibeSet(uint8 indexed vibe, string name);

    constructor(address admin) {
        if (admin == address(0)) revert InvalidAdmin();
        _transferOwnership(admin);
    }

    function setLineage(uint8 lineage, string calldata name, string calldata key) external onlyOwner {
        _setLineage(lineage, name, key);
    }

    function setLineages(uint8[] calldata lineages, string[] calldata names, string[] calldata keys)
        external
        onlyOwner
    {
        if (lineages.length != names.length || names.length != keys.length) revert InvalidBatchLength();

        for (uint256 i = 0; i < lineages.length; i++) {
            _setLineage(lineages[i], names[i], keys[i]);
        }
    }

    function setForm(uint8 stage, uint8 lineage, uint8 form, string calldata name, string calldata artKey_)
        external
        onlyOwner
    {
        _setForm(stage, lineage, form, name, artKey_);
    }

    function setForms(
        uint8[] calldata stages,
        uint8[] calldata lineages,
        uint8[] calldata forms,
        string[] calldata names,
        string[] calldata artKeys
    ) external onlyOwner {
        if (
            stages.length != lineages.length || lineages.length != forms.length || forms.length != names.length
                || names.length != artKeys.length
        ) {
            revert InvalidBatchLength();
        }

        for (uint256 i = 0; i < stages.length; i++) {
            _setForm(stages[i], lineages[i], forms[i], names[i], artKeys[i]);
        }
    }

    function setVibe(uint8 vibe, string calldata name) external onlyOwner {
        _setVibe(vibe, name);
    }

    function setVibes(uint8[] calldata vibes, string[] calldata names) external onlyOwner {
        if (vibes.length != names.length) revert InvalidBatchLength();

        for (uint256 i = 0; i < vibes.length; i++) {
            _setVibe(vibes[i], names[i]);
        }
    }

    function lineageName(uint8 stage, uint8 lineage) external view returns (string memory) {
        if (stage == 1) return _baseLineageName(lineage);

        Entry storage entry = _lineages[lineage];
        if (entry.exists) return entry.name;
        if (lineage == LINEAGE_ORIGIN) return "Origin";
        return "Unknown";
    }

    function formName(uint8 stage, uint8 lineage, uint8 form) external view returns (string memory) {
        Entry storage entry = _forms[_formId(stage, lineage, form)];
        if (entry.exists) return entry.name;
        if (lineage == LINEAGE_ORIGIN) return "Unhatched";
        if (stage == 0) return "Mystery";
        if (stage == 1) {
            return string.concat(_baseLineageName(lineage), " Block");
        }
        return "Unknown";
    }

    function vibeName(uint8 vibe) external view returns (string memory) {
        Entry storage entry = _vibes[vibe];
        if (entry.exists) return entry.name;
        return "Unknown";
    }

    function artKey(uint8 stage, uint8 lineage, uint8 form) external view returns (bytes32) {
        if (stage == 0) return keccak256("T0_DEFAULT");

        Entry storage formEntry = _forms[_formId(stage, lineage, form)];
        if (bytes(formEntry.key).length != 0) return keccak256(bytes(formEntry.key));

        if (stage == 1) return keccak256(bytes(string.concat("T1_", _baseLineageKey(lineage))));

        return bytes32(0);
    }

    function _baseLineageName(uint8 lineage) internal pure returns (string memory) {
        if (lineage == 0) return "Red";
        if (lineage == 1) return "Yellow";
        if (lineage == 2) return "Green";
        if (lineage == 3) return "Cyan";
        if (lineage == 4) return "Blue";
        if (lineage == 5) return "Purple";
        if (lineage == 6) return "Black";
        if (lineage == 7) return "White";
        return "Unknown";
    }

    function _baseLineageKey(uint8 lineage) internal pure returns (string memory) {
        if (lineage == 0) return "RED";
        if (lineage == 1) return "YELLOW";
        if (lineage == 2) return "GREEN";
        if (lineage == 3) return "CYAN";
        if (lineage == 4) return "BLUE";
        if (lineage == 5) return "PURPLE";
        if (lineage == 6) return "BLACK";
        if (lineage == 7) return "WHITE";
        return "UNKNOWN";
    }

    function _setLineage(uint8 lineage, string calldata name, string calldata key) internal {
        _lineages[lineage] = Entry({name: name, key: key, exists: true});
        emit LineageSet(lineage, name, key);
    }

    function _setForm(uint8 stage, uint8 lineage, uint8 form, string calldata name, string calldata artKey_) internal {
        _forms[_formId(stage, lineage, form)] = Entry({name: name, key: artKey_, exists: true});
        emit FormSet(stage, lineage, form, name, artKey_);
    }

    function _setVibe(uint8 vibe, string calldata name) internal {
        _vibes[vibe] = Entry({name: name, key: "", exists: true});
        emit VibeSet(vibe, name);
    }

    function _formId(uint8 stage, uint8 lineage, uint8 form) internal pure returns (uint256) {
        return (uint256(stage) << 16) | (uint256(lineage) << 8) | uint256(form);
    }

    error InvalidBatchLength();
    error InvalidAdmin();
}
