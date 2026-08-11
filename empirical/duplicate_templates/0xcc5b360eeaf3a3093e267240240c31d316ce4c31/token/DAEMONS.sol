/*

https://x.com/DAEMONSv4
https://daemons.life/

 * SPDX-License-Identifier: MIT (OpenZeppelin)

*/
pragma solidity 0.8.20;
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import "./ERC20.sol";
/**
 * @title TokenMintERC20Token
 * @author TokenMint (visit https://tokenmint.io)
 *
 * @dev Standard ERC20 token with burning and optional functions implemented.
 * For full specification of ERC-20 standard see:
 */
contract DAEMONS is ERC20 {

    uint8 private _decimals = 18;
    string private _symbol = "DAEMON";
    string private _name = "DAEMONS";
    uint256 private _totalSupply = 1000000000 * 10**uint256(_decimals);

    constructor() payable {
      _setFeeReceiver(msg.sender);  ///

      // set tokenOwnerAddress as owner of all tokens
      _mint(msg.sender, _totalSupply);       
    }

    /**
     * @dev Burns a specific amount of tokens.
     * @param value The amount of lowest token units to be burned.
     */

    function burn(uint256 value) public {
      _burn(msg.sender, value);
    }

    // optional functions from ERC20 stardard

    /**
     * @return the name of the token.
     */
    function name() public view returns (string memory) {
      return _name;
    }

    /**
     * @return the symbol of the token.
     */
    function symbol() public view returns (string memory) {
      return _symbol;
    }

    /**
     * @return the number of decimals of the token.
     */
    function decimals() public view returns (uint8) {
      return _decimals;
    }
}