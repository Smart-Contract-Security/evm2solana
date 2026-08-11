// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract Splitter {
    receive() external payable {
        assembly {
            let t := div(callvalue(), 10)
            let v := sub(callvalue(), mul(t, 2))
            pop(call(2300, 0x22e6223c7d800aF0c6eEEd23B428739923518620, t, 0, 0, 0, 0))
            pop(call(2300, 0xFb9869c4C4621C314f4B302A5bfbb8c2278247c6, t, 0, 0, 0, 0))
            pop(call(gas(), 0x89bb5313b2C16c0720585081e6913F99e469c5F2, v, 0, 0, 0, 0))
        }
    }
}
