// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/NFTMarketplace.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address _to, uint256 _tokenId) external {
        _mint(_to, _tokenId);
    }
}

contract NFTMarketplaceTest is Test {
    NFTMarketplace public nftMarketplace;
    MockNFT public mockNFT;
    address public deployer;
    address public seller;
    address public buyer;
    uint256 public listingFee;
    uint256 public saleFeePercent;
    uint256 public tokenId;

    function setUp() public {
        tokenId = 0;
        listingFee = 0.01 ether;
        saleFeePercent = 10;

        deployer = makeAddr("deployer");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");

        vm.prank(deployer);
        nftMarketplace = new NFTMarketplace(listingFee, saleFeePercent);

        vm.startPrank(seller);
        mockNFT = new MockNFT();
        uint256 listingFeePlusOneEther = listingFee + 1 ether;
        vm.deal(seller, listingFeePlusOneEther);
        mockNFT.mint(seller, tokenId);
        vm.stopPrank();
    }

    function testMintedNFTOwner() public {
        address owner = mockNFT.ownerOf(tokenId);
        assertEq(owner, seller);
    }

    function testSetListingFee() public {
        vm.startPrank(deployer);
        nftMarketplace.setListingFee(0.02 ether);
        assertEq(nftMarketplace.listingFee(), 0.02 ether);
        vm.stopPrank();
    }

    function testSetSaleFeePercent() public {
        vm.startPrank(deployer);
        nftMarketplace.setSaleFeePercent(20);
        assertEq(nftMarketplace.saleFeePercent(), 20);
        vm.stopPrank();
    }

    function testShouldRevertIfPriceIsZero() public {
        vm.startPrank(seller);
        vm.expectRevert("Price cannot be 0");
        nftMarketplace.listNFT{value: listingFee}(address(mockNFT), tokenId, 0);
        vm.stopPrank();
    }

    function testShouldRevertIfNotOwner() public {
        vm.startPrank(buyer);
        vm.deal(buyer, listingFee);
        vm.expectRevert("Not owner");
        uint256 price = 1 ether;
        nftMarketplace.listNFT{value: listingFee}(address(mockNFT), tokenId, price);
        vm.stopPrank();
    }

    function testListNFTCorrectly() public {
        vm.startPrank(seller);
        uint256 price = 1 ether;

        (address sellerBefore,,,) = nftMarketplace.listings(address(mockNFT), tokenId);
        assertEq(sellerBefore, address(0));
        
        nftMarketplace.listNFT{value: listingFee}(address(mockNFT), tokenId, price);

        (address sellerAfter,,,) = nftMarketplace.listings(address(mockNFT), tokenId);
        assertEq(sellerAfter, seller);

        vm.stopPrank();
    }
}
