
KNOWLEDGE = """
ID	Pattern	Description
1	Address Length	An account address consists of a 32-bytes key, which is represented by the address type.
2	64-bit integers	Solana’s virtual machine registers are 64-bit wide, so 64-bit integers uint64 and int64 are preferable over uint256 and int256.
3	External Call	External calls and contract constructors require explicitly providing the necessary accounts. These accounts must be declared on external functions using annotations (e.g., @account, @mutableSigner) to specify their read, write, and signing permissions.Automatic AccountMeta generation only works in external functions
4	AccountInfo	Retrieving the balance requires accessing the AccountInfo data structure.
5	Compute Unit	Solana utilizes Compute Units (CUs) to quantify computational resources, which fundamentally differs from the EVM gas model.
6	No msg.sender	The msg.sender is not available in Solana.
7	No ecrecover()	There is no ecrecover() builtin function because Solana does not use the ECDSA algorithm
8	New Constructor	New Contract in EVM, Contract.new in Solana
9	No gas/salt	The gas or salt cannot be set on Solana. However, when creating a contract on Solana, the address of the new account must be set using address.
10	No try-catch	Try-catch statements do not work on Solana.
11	No error definitions/reverts	Error definitions and reverts with error messages are not yet working for Solana.
12	No value transfer (msg.value/value)	Value transfer via function calls is unsupported, prohibiting the value: parameter in external calls and constructors.The msg.value is not supported
13	Unavailable Yul builtins	stop(),signextend(i, x),keccak256(p, n),pc(),pop(x),mload(p),mstore(p, v),mstore8(p, v),sload(p),sstore(p, v),msize(),calldataload(p),calldatasize(),calldatacopy(t, f, s),codesize(),codecopy(t, f, s),extcodesize(a),extcodecopy(a, t, f, s),returndatasize(),returndatacopy(t, f, s),extcodehash(a),create(v, p, n),create2(v, p, n, s),call(g, a, v, in,insize, out, outsize),callcode(g, a, v, in,insize, out, outsize),delegatecall(g, a, in,insize, out, outsize),staticcall(g, a, in,insize, out, outsize),return(p, s),revert(p, s),selfdestruct(a),log0(p, s),log1(p, s, t1),log2(p, s, t1, t2),log3(p, s, t1, t2, t3),log4(p, s, t1, t2, t3, t4),chainid(),basefee()
14	ERC-20 interface	The ERC-20 interface is not compatible with Solana at the moment. Solana uses SPL Token
15	Program ID	When making external calls on Solana, the target program must be specified. Solang uses `@program_id` for this adaptation.
16	Construct Annotations	@payer,@space,@seed
17	No payable effect	The payable keyword has no effect
18	No receive()	receive() functions are not permitted on the Solana target.
19	Solana builtin imports	Some builtin functionality is only available after importing. The following structs can be imported via the special builtin import file solana.
20	abi.encodePacked	Packed encoded uses little endian encoding, as WASM and SBF are little endian virtual machines.
21	Contract Type	Contracts cannot be used as first-class types in function parameters, return values, or local variables.
22	this returns program account	On Solana, this returns the program account. If you are looking for the data account, please use tx.accounts.dataAccount.key.Dual account model: program account and data account
23	No indexed event fields	On Solana, the indexed event field attribute has no effect.
24	No tx.origin	The address that started this transaction. Not available on Polkadot or Solana.
25	No gas on external	The gas cannot be set on Solana for external calls.
26	No delegatecall	The delegatecall is not available on Solana.
27	No send or transfer	On Solana, there are no transfer and send functions.
28	No gasleft()	The gasleft() is not available on Solana.
29	msg.sig	The msg.sig assumes the semantic role of a bytes8 discriminator.
30	abi.encodeWithSelector/abi.encodeWithSignature	In addition, a discriminator for a Solidity function on Solana are the first eight bytes of the sha-256 hash of its name converted to camel case and preceded by the prefix global
31	No tx.gasprice	tx.gasprice is not available on Solana.
32	No selfdestruct	This function does not exist on Solana.
33	No blockhash	This function is not available on Solana.
34	Clock Account	Solana requires the clock account to present in the account for the instruction to use any of the block fields.
35	block.number	On Solana, block.number gives the slot number rather than the block height.
36	No block properties	block.gaslimit,block.coinbase,block.difficulty
37	pragma solidity unnecessary	There is no need for a pragma solidity statement when using Solang.
38	Ethereum currency units warning	Note that the Ethereum currency denominations ether, gwei, and wei are available when not compiling for Ethereum, but they will produce warnings.
"""