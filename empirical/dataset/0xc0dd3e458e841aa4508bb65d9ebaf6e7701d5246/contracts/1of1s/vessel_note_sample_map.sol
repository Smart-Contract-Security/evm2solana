// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Vessel_Piano_Map is Ownable {
    mapping(uint8 => uint256) private _noteToSampleCraft;

    event NoteSampleCraftSet(uint8 indexed midiNote, uint256 indexed sampleCraft);

    error LengthMismatch();

    constructor() Ownable(msg.sender) {
        _setInitialValues();
    }

    function noteToSampleCraft(uint8 midiNote) external view returns (uint256) {
        return _noteToSampleCraft[midiNote];
    }

    function setNoteSampleCraft(uint8 midiNote, uint256 sampleCraft) external onlyOwner {
        _noteToSampleCraft[midiNote] = sampleCraft;
        emit NoteSampleCraftSet(midiNote, sampleCraft);
    }

    function batchSetNoteSampleCraft(
        uint8[] calldata midiNotes,
        uint256[] calldata sampleCrafts
    ) external onlyOwner {
        if (midiNotes.length != sampleCrafts.length) revert LengthMismatch();

        for (uint256 i; i < midiNotes.length; i++) {
            _noteToSampleCraft[midiNotes[i]] = sampleCrafts[i];
            emit NoteSampleCraftSet(midiNotes[i], sampleCrafts[i]);
        }
    }

    function _setInitialValues() internal {
        _noteToSampleCraft[21] = 7985;
        _noteToSampleCraft[22] = 7945;
        _noteToSampleCraft[23] = 8141;
        _noteToSampleCraft[24] = 8120;
        _noteToSampleCraft[25] = 8151;
        _noteToSampleCraft[26] = 8102;
        _noteToSampleCraft[27] = 8098;
        _noteToSampleCraft[28] = 8083;
        _noteToSampleCraft[29] = 7893;
        _noteToSampleCraft[30] = 8051;
        _noteToSampleCraft[31] = 7892;
        _noteToSampleCraft[32] = 8081;
        _noteToSampleCraft[33] = 7969;
        _noteToSampleCraft[34] = 7904;
        _noteToSampleCraft[35] = 8111;
        _noteToSampleCraft[36] = 8090;
        _noteToSampleCraft[37] = 8086;
        _noteToSampleCraft[38] = 8105;
        _noteToSampleCraft[39] = 7994;
        _noteToSampleCraft[40] = 8064;
        _noteToSampleCraft[41] = 8006;
        _noteToSampleCraft[42] = 8017;
        _noteToSampleCraft[43] = 8021;
        _noteToSampleCraft[44] = 7891;
        _noteToSampleCraft[45] = 7887;
        _noteToSampleCraft[46] = 7959;
        _noteToSampleCraft[47] = 7947;
        _noteToSampleCraft[48] = 7941;
        _noteToSampleCraft[49] = 7935;
        _noteToSampleCraft[50] = 7868;
        _noteToSampleCraft[51] = 7871;
        _noteToSampleCraft[52] = 7929;
        _noteToSampleCraft[53] = 7927;
        _noteToSampleCraft[54] = 7859;
        _noteToSampleCraft[55] = 7889;
        _noteToSampleCraft[56] = 7867;
        _noteToSampleCraft[57] = 7803;
        _noteToSampleCraft[58] = 7922;
        _noteToSampleCraft[59] = 7857;
        _noteToSampleCraft[60] = 7826;
        _noteToSampleCraft[61] = 7849;
        _noteToSampleCraft[62] = 7805;
        _noteToSampleCraft[63] = 7786;
        _noteToSampleCraft[64] = 7771;
        _noteToSampleCraft[65] = 7760;
        _noteToSampleCraft[66] = 7884;
        _noteToSampleCraft[67] = 7883;
        _noteToSampleCraft[68] = 7864;
        _noteToSampleCraft[69] = 7748;
        _noteToSampleCraft[70] = 7820;
        _noteToSampleCraft[71] = 7811;
        _noteToSampleCraft[72] = 7701;
        _noteToSampleCraft[73] = 7572;
        _noteToSampleCraft[74] = 7557;
        _noteToSampleCraft[75] = 7700;
        _noteToSampleCraft[76] = 7694;
        _noteToSampleCraft[77] = 7577;
        _noteToSampleCraft[78] = 7699;
        _noteToSampleCraft[79] = 7628;
        _noteToSampleCraft[80] = 7642;
        _noteToSampleCraft[81] = 7633;
        _noteToSampleCraft[82] = 7698;
        _noteToSampleCraft[83] = 7575;
        _noteToSampleCraft[84] = 7381;
        _noteToSampleCraft[85] = 7563;
        _noteToSampleCraft[86] = 7524;
        _noteToSampleCraft[87] = 7441;
        _noteToSampleCraft[88] = 7447;
        _noteToSampleCraft[89] = 7641;
        _noteToSampleCraft[90] = 7582;
        _noteToSampleCraft[91] = 7315;
        _noteToSampleCraft[92] = 6269;
        _noteToSampleCraft[93] = 7053;
        _noteToSampleCraft[94] = 6091;
        _noteToSampleCraft[95] = 5190;
        _noteToSampleCraft[96] = 5007;
        _noteToSampleCraft[97] = 4284;
        _noteToSampleCraft[98] = 4673;
        _noteToSampleCraft[99] = 3572;
        _noteToSampleCraft[100] = 3575;
        _noteToSampleCraft[101] = 4026;
        _noteToSampleCraft[102] = 3818;
        _noteToSampleCraft[103] = 2661;
        _noteToSampleCraft[104] = 1459;
        _noteToSampleCraft[105] = 1561;
        _noteToSampleCraft[106] = 1379;
        _noteToSampleCraft[107] = 1303;
        _noteToSampleCraft[108] = 1162;
        _noteToSampleCraft[109] = 781;
    }
}