from dataclasses import dataclass

@dataclass(frozen=True)
class PatternDefine:
    # 1-38
    id: int
    # pattern name
    name: str
    # description
    description: str

@dataclass
class ScanHit:
    pattern_id: str
    file: str
    line: int
    code_snippet: str
    src: str

    def to_dict(self) -> dict:
        return {
            "pattern_id": self.pattern_id,
            "file": self.file,
            "line": self.line,
            "code_snippet": self.code_snippet,
            "src": self.src,
        }

# Pattern 1-38
# detector_summary coms from our consensus in dual coding
_DEFINES: list[PatternDefine] = [
    PatternDefine(1, "Address length", 
        "An account address consists of a 32-bytes key."),
    PatternDefine(2, "64-bit integers",
        "Solana’s virtual machine registers are 64-bit wide, uint64/int64 are preferable."),
    PatternDefine(3, "External call accounts",
        "External calls and contract constructors require explicitly providing the necessary accounts."),
    PatternDefine(4, "AccountInfo balance access",
        "Retrieving the balance requires accessing the AccountInfo data structure."),
    PatternDefine(5, "Compute unit model", 
        "Solana utilizes Compute Units (CUs) to quantify computational resources, which fundamentally differs from the EVM gas model."),
    PatternDefine(6, "Unavailable msg.sender",
        "The msg.sender is not available in Solana."),
    PatternDefine(7, "Unavailable ecrecover",
        "There is no ecrecover() builtin function because Solana does not use the ECDSA algorithm."),
    PatternDefine(8, "Changed constructor syntax", 
        "Use Contract.new instead of new Contract."),
    PatternDefine(9, "Unavailable gas/salt in creation",
        "gas/salt unsettable; supply the new account's address."),
    PatternDefine(10, "Unavailable try-catch",
        "Try-catch statements do not work on Solana."),
    PatternDefine(11, "Unavailable error definitions",
        "Error definitions and reverts with error messages are not yet working for Solana."),
    PatternDefine(12, "Unavailable value transfer",
        "No value: parameter on calls and no msg.value."),    
    PatternDefine(13, "Unavailable Yul builtins",
        "Inline-assembly (Yul) builtins are unavailable."),
    PatternDefine(14, "ERC-20/SPL token gap",
        "The ERC-20 interface is not compatible with Solana at the moment. Solana uses SPL Token."),
    PatternDefine(15, "Required @program_id",
        "External calls must name the target via @program_id."),
    PatternDefine(16, "Required constructor annotations",
        "Constructors require @payer, @space, and @seed."),
    PatternDefine(17, "Ineffective payable",
        "payable has no effect."),
    PatternDefine(18, "Unavailable receive",
        "receive() functions are not permitted."),
    PatternDefine(19, "Required Solana builtin imports",
        "Some builtins must be imported from the solana file."),
    PatternDefine(20, "Little-endian packed encoding",
        "abi.encodePacked uses little-endian encoding (SBF)."),
    PatternDefine(21, "Contracts not usable as types",
        "Contracts cannot be used as first-class types in function parameters, return values, or local variables."),
    PatternDefine(22, "Changed this semantics",
        "this is the program account; data account via tx.accounts.dataAccount.key."),         
    PatternDefine(23, "Ineffective indexed events",
        "indexed event fields have no effect."),
    PatternDefine(24, "Unavailable tx.origin",
        "tx.origin is unavailable."),
    PatternDefine(25, "Unavailable gas on external calls",
        "gas cannot be set on external calls."),
    PatternDefine(26, "Unavailable delegatecall",
        "delegatecall is unavailable."),
    PatternDefine(27, "Unavailable send/transfer",
        "No send/transfer functions."),
    PatternDefine(28, "Unavailable gasleft",
        "gasleft() is unavailable."),
    PatternDefine(29, "Changed msg.sig width",
        "msg.sig assumes the semantic role of a bytes8 discriminator."),        
    PatternDefine(30, "Changed ABI selector/discriminator",
        "Discriminator: first 8 bytes of the SHA-256 of the camel-case name, prefixed global."),
    PatternDefine(31, "Unavailable tx.gasprice",
        "tx.gasprice is unavailable."),
    PatternDefine(32, "Unavailable selfdestruct",
        "selfdestruct() does not exist."),
    PatternDefine(33, "Unavailable blockhash",
        "blockhash() is unavailable."),
    PatternDefine(34, "Required clock account",
        "Block fields require the clock account to be passed in."),
    PatternDefine(35, "Changed block.number semantics",
        "block.number is the slot number, not the block height."),
    PatternDefine(36, "Unavailable block properties",
        "block.gaslimit/coinbase/difficulty are unavailable."),
    PatternDefine(37, "Ignored pragma pragma solidity",
        "pragma solidity is unnecessary."),
    PatternDefine(38, "Ethereum currency units warning",
        "ether/gwei/wei are accepted but warn off-Ethereum."),
]