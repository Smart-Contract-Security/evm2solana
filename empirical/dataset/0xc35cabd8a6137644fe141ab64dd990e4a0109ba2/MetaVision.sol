// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Importuojame atviro kodo bibliotekas, kurios atlieka 90% nuobodaus darbo
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MetaVision is ERC20, Ownable {
    
    // 🔴 ŠTAI ČIA YRA TAI, KAS ATMUŠĖ TAVO BOTĄ:
    // Iš pat pradžių prekyba yra užblokuota (false) visiems, išskyrus tave.
    bool public tradingOpen = false; 

    // Konstruktorius (paleidžiamas tik 1 kartą - sukūrimo momentu)
    constructor() ERC20("MetaVision", "MV") Ownable(msg.sender) {
        // Nukaldiname 1 Milijardą žetonų ir padedame juos į tavo piniginę
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    // 🟢 ŠI FUNKCIJA - TAVO GAIDUKAS:
    // Kai tu įdedi likvidumą į keityklą ir paspaudi šį mygtuką, pasileidžia pragaras (botai pradeda pirkti).
    function openTrading() external onlyOwner {
        tradingOpen = true;
    }

    // Modifikuojame standartinę pervedimo funkciją, kad veiktų mūsų apsauga
    function _update(address from, address to, uint256 value) internal override {
        // Jei prekyba dar uždaryta, judinti žetonus gali TIK kūrėjas (tu)
        if (!tradingOpen) {
            require(from == owner() || to == owner(), "Prekyba dar neaktyvuota! (Anti-Sniper atmetimas)");
        }
        
        // Jei prekyba atvira arba siuntėjas esi tu - leidžiame transakciją
        super._update(from, to, value);
    }
}