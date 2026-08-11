// SPDX-License-Identifier: MIT

import 'solana';

interface ICreatorToken {
    event TransferValidatorUpdated(address oldValidator, address newValidator);

    function getTransferValidator() external view returns (address validator);

    function getTransferValidationFunction()
        external
        view
        returns (bytes4 functionSignature, bool isViewFunction);

    function setTransferValidator(address validator) external;
}

interface ILegacyCreatorToken {
    event TransferValidatorUpdated(address oldValidator, address newValidator);

    function getTransferValidator() external view returns (address validator);

    function setTransferValidator(address validator) external;
}