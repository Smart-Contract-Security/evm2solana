// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SolicAbstract} from "./SolicAbstract.sol";

interface Vm {
    function deal(address account, uint256 amount) external;
    function prank(address account) external;
    function startPrank(address account) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes calldata revertData) external;
}

contract SolicAbstractTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    SolicAbstract internal nft;
    address internal owner = address(this);
    address internal user = address(0xA11CE);
    address internal other = address(0xB0B);
    address payable internal withdrawTo = payable(address(0xCAFE));

    function setUp() public {
        _deployFresh();
    }

    function _deployFresh() internal {
        nft = new SolicAbstract(
            "SOLIC ABSTRACT",
            "SLCA",
            owner,
            "ipfs://meta/",
            "ipfs://meta/contract.json"
        );
        vm.deal(user, 10 ether);
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "uint mismatch");
    }

    function assertEq(bool actual, bool expected) internal pure {
        require(actual == expected, "bool mismatch");
    }

    function assertEq(address actual, address expected) internal pure {
        require(actual == expected, "address mismatch");
    }

    function assertEq(string memory actual, string memory expected) internal pure {
        require(keccak256(bytes(actual)) == keccak256(bytes(expected)), "string mismatch");
    }

    function testDeploymentConfig() public {
        _deployFresh();
        assertEq(nft.name(), "SOLIC ABSTRACT");
        assertEq(nft.symbol(), "SLCA");
        assertEq(nft.MAX_SUPPLY(), 5151);
        assertEq(nft.mintPrice(), 0.0003 ether);
        assertEq(nft.mintOpen(), false);
        assertEq(nft.contractURI(), "ipfs://meta/contract.json");
    }

    function testClosedMintAndOpenClose() public {
        _deployFresh();
        vm.deal(address(this), 1 ether);
        try nft.mint{value: nft.mintPrice()}(1) {
            revert("expected closed mint revert");
        } catch Error(string memory reason) {
            assertEq(reason, "Mint closed");
        }

        nft.openMint();
        assertEq(nft.mintOpen(), true);

        nft.closeMint();
        assertEq(nft.mintOpen(), false);
    }

    function testPublicMintExactEthAndWalletTracking() public {
        _deployFresh();
        nft.openMint();

        vm.prank(user);
        nft.mint{value: 0.0006 ether}(2);

        assertEq(nft.balanceOf(user), 2);
        assertEq(nft.mintedByWallet(user), 2);
        assertEq(nft.tokenURI(1), "ipfs://meta/1.json");
    }

    function testInvalidPublicMintsRevert() public {
        _deployFresh();
        nft.openMint();
        uint256 price = nft.mintPrice();

        vm.startPrank(user);
        vm.expectRevert(bytes("Zero quantity"));
        nft.mint(0);

        vm.expectRevert(bytes("Exceeds max per tx"));
        nft.mint{value: price * 6}(6);

        vm.expectRevert(bytes("Wrong ETH amount"));
        nft.mint{value: price + 1}(1);

        vm.expectRevert(bytes("Wrong ETH amount"));
        nft.mint{value: price - 1}(1);

        nft.mint{value: price * 5}(5);
        nft.mint{value: price * 5}(5);

        vm.expectRevert(bytes("Exceeds wallet limit"));
        nft.mint{value: price}(1);
        vm.stopPrank();
    }

    function testOwnerCommandsAndProtection() public {
        _deployFresh();
        vm.prank(user);
        vm.expectRevert();
        nft.openMint();

        nft.setMintPrice(1);
        nft.setMaxPerTx(3);
        nft.setMaxPerWallet(4);
        nft.setBaseURI("ipfs://new/");
        nft.setContractURI("ipfs://new/contract.json");
        nft.setRoyaltyInfo(other, 750);
        nft.ownerMint(user, 1);

        assertEq(nft.owner(), owner);
        assertEq(nft.tokenURI(1), "ipfs://new/1.json");
    }

    function testWithdrawAllAndExactAmount() public {
        _deployFresh();
        nft.openMint();
        uint256 price = nft.mintPrice();

        vm.prank(user);
        nft.mint{value: price * 2}(2);

        vm.expectRevert(bytes("Zero address"));
        nft.withdrawAmount(payable(address(0)), 1);

        vm.expectRevert(bytes("Insufficient balance"));
        nft.withdrawAmount(withdrawTo, price * 3);

        uint256 beforeAmount = withdrawTo.balance;
        nft.withdrawAmount(withdrawTo, price);
        assertEq(withdrawTo.balance - beforeAmount, price);

        uint256 beforeAll = withdrawTo.balance;
        nft.withdrawAll(withdrawTo);
        assertEq(withdrawTo.balance - beforeAll, price);
    }

    function testOwnerMintCannotExceedSupply() public {
        _deployFresh();
        vm.expectRevert(bytes("Sold out"));
        nft.ownerMint(user, 5152);
    }
}
