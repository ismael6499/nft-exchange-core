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

contract RevertingReceiver {
    receive() external payable {
        revert();
    }
}

contract RevertingSeller {
    NFTMarketplace market;
    IERC721 nft;

    constructor(address _market, address _nft) {
        market = NFTMarketplace(_market);
        nft = IERC721(_nft);
    }

    function list(uint256 _tokenId, uint256 _price) external {
        uint256 fee = market.listingFee();
        nft.approve(address(market), _tokenId);
        market.listNFT{value: fee}(address(nft), _tokenId, _price);
    }

    receive() external payable {
        revert();
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

    function testSetSaleFeePercentShouldRevertIfPercentIsGreaterThan100() public {
        vm.startPrank(deployer);
        vm.expectRevert("Percent cannot exceed 100%");
        nftMarketplace.setSaleFeePercent(10001);
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

    function testShouldRevertIfIncorrectListingFee() public {
        vm.startPrank(seller);
        vm.deal(seller, listingFee + 1);
        vm.expectRevert("Incorrect listing fee");
        uint256 price = 1 ether;
        nftMarketplace.listNFT{value: listingFee + 1}(address(mockNFT), tokenId, price);
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

    function testCancelListingShouldRevertIfNotOwner() public {
        vm.prank(seller);
        nftMarketplace.listNFT{value: listingFee}(address(mockNFT), tokenId, 1 ether);

        vm.startPrank(buyer);
        vm.expectRevert("Not owner");
        nftMarketplace.cancelList(address(mockNFT), tokenId);
        vm.stopPrank();
    }

    function testCancelListingCorrectly() public {
        vm.startPrank(seller);
        uint256 price = 1 ether;
        nftMarketplace.listNFT{value: listingFee}(address(mockNFT), tokenId, price);

        (address sellerBefore,,,) = nftMarketplace.listings(address(mockNFT), tokenId);
        assertEq(sellerBefore, seller);
        
        nftMarketplace.cancelList(address(mockNFT), tokenId);

        (address sellerAfter,,,) = nftMarketplace.listings(address(mockNFT), tokenId);
        assertEq(sellerAfter, address(0));

        vm.stopPrank();
    }

    function testCannotBuyNotListedNFT() public {
        vm.startPrank(buyer);
        vm.expectRevert("NFT not listed");
        nftMarketplace.buyNFT(address(mockNFT), tokenId);
        vm.stopPrank();
    }
    
    function testCannotBuyNotOwnerNFT() public {
        vm.startPrank(seller);
        uint256 price = 1 ether;
        vm.deal(seller, price + listingFee);
        nftMarketplace.listNFT{value: listingFee}(address(mockNFT), tokenId, price);

        vm.expectRevert("You are the owner");
        nftMarketplace.buyNFT{value: price}(address(mockNFT), tokenId);
        vm.stopPrank();
    }

    function testCannotBuyWithIncorrectValue() public {
        vm.startPrank(seller);
        uint256 price = 1 ether;
        vm.deal(seller, listingFee);
        nftMarketplace.listNFT{value: listingFee}(address(mockNFT), tokenId, price);
        vm.stopPrank();
        
        vm.startPrank(buyer);
        vm.deal(buyer, price);
        vm.expectRevert("Not enough ETH");
        nftMarketplace.buyNFT{value: (price - 1)}(address(mockNFT), tokenId);
        vm.stopPrank();
    }

    function testShouldBuyCorrectly() public {
        vm.startPrank(seller);
        uint256 price = 1 ether;
        vm.deal(seller, listingFee);
        nftMarketplace.listNFT{value: listingFee}(address(mockNFT), tokenId, price);        
        mockNFT.approve(address(nftMarketplace), tokenId);
        uint256 balanceBefore = seller.balance;
        vm.stopPrank();
        
        vm.startPrank(buyer);
        vm.deal(buyer, price);
        uint256 BASIS_POINTS = 10000;
        uint256 saleFee = (price * saleFeePercent) / BASIS_POINTS;
        nftMarketplace.buyNFT{value: price}(address(mockNFT), tokenId);
        vm.stopPrank();   
        
        assertEq(seller.balance, balanceBefore + price - saleFee);
    }
    function testShouldRevertIfListingFeeTransferFailed() public {
        RevertingReceiver receiver = new RevertingReceiver();
        
        vm.prank(deployer);
        nftMarketplace.transferOwnership(address(receiver));
        
        vm.startPrank(seller);
        vm.deal(seller, listingFee);
        vm.expectRevert("Transfer of listing fee failed");
        uint256 price = 1 ether;
        nftMarketplace.listNFT{value: listingFee}(address(mockNFT), tokenId, price);
        vm.stopPrank();
    }

    function testShouldRevertIfSellerTransferFailed() public {
        RevertingSeller revertingSeller = new RevertingSeller(address(nftMarketplace), address(mockNFT));
        uint256 newTokenId = 2;
        
        vm.prank(seller); 
        mockNFT.mint(address(revertingSeller), newTokenId);
        
        vm.deal(address(revertingSeller), listingFee);
        
        uint256 price = 1 ether;
        revertingSeller.list(newTokenId, price);
        
        vm.startPrank(buyer);
        vm.deal(buyer, price);
        vm.expectRevert("Transfer to seller failed");
        nftMarketplace.buyNFT{value: price}(address(mockNFT), newTokenId);
        vm.stopPrank();
    }

    function testShouldRevertIfSaleFeeTransferFailed() public {
        vm.startPrank(seller);
        vm.deal(seller, listingFee);
        uint256 price = 1 ether;
        nftMarketplace.listNFT{value: listingFee}(address(mockNFT), tokenId, price);
        mockNFT.approve(address(nftMarketplace), tokenId);
        vm.stopPrank();
        
        RevertingReceiver receiver = new RevertingReceiver();
        vm.prank(deployer);
        nftMarketplace.transferOwnership(address(receiver));
        
        vm.startPrank(buyer);
        vm.deal(buyer, price);
        vm.expectRevert("Transfer of sale fee failed");
        nftMarketplace.buyNFT{value: price}(address(mockNFT), tokenId);
        vm.stopPrank();
    }
}
