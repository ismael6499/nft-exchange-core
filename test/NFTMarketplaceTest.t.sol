// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/NFTMarketplace.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// --- Mocks & Helpers ---

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}
    function mint(address _to, uint256 _tokenId) external {
        _mint(_to, _tokenId);
    }
}

contract RevertingReceiver {
    receive() external payable { revert(); }
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
        market.listNft{value: fee}(address(nft), _tokenId, _price);
    }
    receive() external payable { revert(); }
}

// --- Main Test Suite ---

contract NFTMarketplaceTest is Test {
    
    NFTMarketplace public marketplace;
    MockNFT public mockNFT;
    
    address public deployer = makeAddr("deployer");
    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");
    
    uint256 public listingFee = 0.01 ether;
    uint256 public platformFeeBps = 10; // 0.1%
    uint256 public constant TOKEN_ID = 0;

    function setUp() public {
        vm.startPrank(deployer);
        marketplace = new NFTMarketplace(listingFee, platformFeeBps);
        mockNFT = new MockNFT();
        vm.stopPrank();

        // Setup seller
        vm.startPrank(seller);
        vm.deal(seller, 100 ether);
        mockNFT.mint(seller, TOKEN_ID);
        mockNFT.setApprovalForAll(address(marketplace), true); // Vital for listing
        vm.stopPrank();
    }

    function test_Setup_CorrectValues() public view {
        assertEq(marketplace.listingFee(), listingFee);
        assertEq(marketplace.platformFeeBps(), platformFeeBps);
        assertEq(mockNFT.ownerOf(TOKEN_ID), seller);
    }

    // --- Admin Tests ---

    function test_SetFees_AsOwner() public {
        vm.startPrank(deployer);
        
        marketplace.setListingFee(0.02 ether);
        assertEq(marketplace.listingFee(), 0.02 ether);

        marketplace.setPlatformFee(200);
        assertEq(marketplace.platformFeeBps(), 200);
        
        vm.stopPrank();
    }

    function test_SetFees_RevertIf_TooHigh() public {
        vm.prank(deployer);
        vm.expectRevert(NFTMarketplace.FeeTooHigh.selector);
        marketplace.setPlatformFee(10001);
    }

    // --- Listing Tests ---

    function test_List_Success() public {
        vm.startPrank(seller);
        uint256 price = 1 ether;

        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, price);
        
        (address listedSeller,,, uint256 listedPrice) = marketplace.listings(address(mockNFT), TOKEN_ID);
        assertEq(listedSeller, seller);
        assertEq(listedPrice, price);
        vm.stopPrank();
    }

    function test_List_Success_WithSpecificApproval() public {
        // Test listing with approve() instead of setApprovalForAll()
        uint256 newTokenId = 1;
        vm.startPrank(seller);
        mockNFT.mint(seller, newTokenId);
        
        // Ensure no global approval
        mockNFT.setApprovalForAll(address(marketplace), false);
        
        // Specific approval
        mockNFT.approve(address(marketplace), newTokenId);

        marketplace.listNft{value: listingFee}(address(mockNFT), newTokenId, 1 ether);
        
        (address listedSeller,,,) = marketplace.listings(address(mockNFT), newTokenId);
        assertEq(listedSeller, seller);
        vm.stopPrank();
    }

    function test_List_Success_ZeroListingFee() public {
        vm.prank(deployer);
        marketplace.setListingFee(0);

        vm.startPrank(seller);
        // Should not revert even if value is 0
        marketplace.listNft{value: 0}(address(mockNFT), TOKEN_ID, 1 ether);
        
        (address listedSeller,,,) = marketplace.listings(address(mockNFT), TOKEN_ID);
        assertEq(listedSeller, seller);
        vm.stopPrank();
    }

    function test_List_RevertIf_NotApproved() public {
        uint256 newTokenId = 99;
        vm.startPrank(seller);
        mockNFT.mint(seller, newTokenId);
        
        // Remove global approval
        mockNFT.setApprovalForAll(address(marketplace), false);

        vm.expectRevert(NFTMarketplace.NotApprovedForMarketplace.selector);
        marketplace.listNft{value: listingFee}(address(mockNFT), newTokenId, 1 ether);
        vm.stopPrank();
    }

    function test_List_RevertIf_PriceZero() public {
        vm.startPrank(seller);
        vm.expectRevert(NFTMarketplace.PriceMustBeAboveZero.selector);
        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, 0);
        vm.stopPrank();
    }

    function test_List_RevertIf_IncorrectFee() public {
        vm.startPrank(seller);
        vm.expectRevert(NFTMarketplace.ListingFeeInvalid.selector);
        marketplace.listNft{value: listingFee - 1}(address(mockNFT), TOKEN_ID, 1 ether);
        vm.stopPrank();
    }

    function test_List_RevertIf_NotOwner() public {
        vm.startPrank(buyer); // Random user
        vm.deal(buyer, listingFee);
        
        vm.expectRevert(NFTMarketplace.NotOwner.selector);
        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, 1 ether);
        vm.stopPrank();
    }

    // --- Buying Tests ---

    function test_Buy_Success() public {
        uint256 price = 1 ether;
        
        vm.prank(seller);
        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, price);

        vm.startPrank(buyer);
        vm.deal(buyer, price);
        
        uint256 sellerBalanceBefore = seller.balance;
        
        marketplace.buyNft{value: price}(address(mockNFT), TOKEN_ID);
        
        assertEq(mockNFT.ownerOf(TOKEN_ID), buyer);
        
        uint256 fee = (price * platformFeeBps) / 10000;
        assertEq(seller.balance, sellerBalanceBefore + (price - fee));
        vm.stopPrank();
    }

    function test_Buy_Success_ZeroPlatformFee() public {
        // Set fee to 0 to test the 'if (platformFee > 0)' branch logic
        vm.prank(deployer);
        marketplace.setPlatformFee(0);

        uint256 price = 1 ether;
        vm.prank(seller);
        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, price);

        vm.startPrank(buyer);
        vm.deal(buyer, price);
        
        uint256 sellerBalanceBefore = seller.balance;
        marketplace.buyNft{value: price}(address(mockNFT), TOKEN_ID);
        
        // Seller gets full price
        assertEq(seller.balance, sellerBalanceBefore + price);
        vm.stopPrank();
    }

    function test_Buy_RevertIf_NotListed() public {
        vm.startPrank(buyer);
        vm.deal(buyer, 1 ether);
        
        vm.expectRevert(NFTMarketplace.ItemNotListed.selector);
        marketplace.buyNft{value: 1 ether}(address(mockNFT), TOKEN_ID); // Not listed yet
        vm.stopPrank();
    }

    function test_Buy_RevertIf_PriceMismatch() public {
        uint256 price = 1 ether;
        vm.prank(seller);
        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, price);

        vm.startPrank(buyer);
        vm.deal(buyer, price);
        
        vm.expectRevert(abi.encodeWithSelector(
            NFTMarketplace.PriceMismatch.selector,
            price,
            price - 0.1 ether
        ));
        marketplace.buyNft{value: price - 0.1 ether}(address(mockNFT), TOKEN_ID);
        vm.stopPrank();
    }

    function test_Buy_RevertIf_SellerIsBuyer() public {
        uint256 price = 1 ether;
        vm.prank(seller);
        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, price);

        vm.startPrank(seller); 
        vm.expectRevert(NFTMarketplace.SellerCannotBeBuyer.selector);
        marketplace.buyNft{value: price}(address(mockNFT), TOKEN_ID);
        vm.stopPrank();
    }

    // --- Cancel Tests ---

    function test_Cancel_Success() public {
        vm.startPrank(seller);
        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, 1 ether);
        marketplace.cancelList(address(mockNFT), TOKEN_ID);
        
        (address listedSeller,,,) = marketplace.listings(address(mockNFT), TOKEN_ID);
        assertEq(listedSeller, address(0));
        vm.stopPrank();
    }

    function test_Cancel_RevertIf_NotOwner() public {
        vm.startPrank(seller);
        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, 1 ether);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert(NFTMarketplace.NotOwner.selector);
        marketplace.cancelList(address(mockNFT), TOKEN_ID);
        vm.stopPrank();
    }

    // --- Edge Cases / Failures ---

    function test_RevertIf_ListingFeeTransferFails() public {
        RevertingReceiver nastyOwner = new RevertingReceiver();
        
        vm.prank(deployer);
        marketplace.transferOwnership(address(nastyOwner));

        vm.startPrank(seller);
        vm.expectRevert(NFTMarketplace.FeeTransferFailed.selector);
        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, 1 ether);
        vm.stopPrank();
    }

    function test_RevertIf_SellerTransferFails() public {
        RevertingSeller badSeller = new RevertingSeller(address(marketplace), address(mockNFT));
        uint256 newTokenId = 5;

        vm.prank(seller);
        mockNFT.mint(address(badSeller), newTokenId);

        vm.deal(address(badSeller), listingFee);
        badSeller.list(newTokenId, 1 ether);

        vm.startPrank(buyer);
        vm.deal(buyer, 1 ether);
        
        vm.expectRevert(NFTMarketplace.FeeTransferFailed.selector);
        marketplace.buyNft{value: 1 ether}(address(mockNFT), newTokenId);
        vm.stopPrank();
    }

    function test_RevertIf_PlatformFeeTransferFails() public {
        // Setup: Listing fee is paid (to deployer), but Platform fee fails (to nastyOwner)
        uint256 price = 1 ether;
        
        // 1. List item correctly
        vm.prank(seller);
        marketplace.listNft{value: listingFee}(address(mockNFT), TOKEN_ID, price);

        // 2. Change owner to reverting contract to break the *sale* fee transfer
        RevertingReceiver nastyOwner = new RevertingReceiver();
        vm.prank(deployer);
        marketplace.transferOwnership(address(nastyOwner));

        // 3. Buy try
        vm.startPrank(buyer);
        vm.deal(buyer, price);
        
        vm.expectRevert(NFTMarketplace.FeeTransferFailed.selector);
        marketplace.buyNft{value: price}(address(mockNFT), TOKEN_ID);
        vm.stopPrank();
    }
}