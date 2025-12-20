// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NFTMarketplace is Ownable, ReentrancyGuard {

    error PriceMustBeAboveZero();
    error NotOwner();
    error NotApprovedForMarketplace();
    error ListingFeeInvalid();
    error ItemNotListed();
    error PriceMismatch(uint256 expected, uint256 sent);
    error SellerCannotBeBuyer();
    error FeeTransferFailed();
    error FeeTooHigh();

    struct Listing {
        address seller;
        address nftAddress;
        uint256 tokenId;
        uint256 price;
    }

    mapping(address => mapping(uint256 => Listing)) public listings;
    
    uint256 public listingFee;
    uint256 public platformFeeBps; 
    uint256 private constant MAX_BPS = 10000;

    event NFTListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event NFTBought(address indexed buyer, address seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event NFTCancelled(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);
    event ListingFeeUpdated(uint256 newFee);
    event PlatformFeeUpdated(uint256 newFeeBps);

    constructor(uint256 _listingFee, uint256 _platformFeeBps) Ownable(msg.sender) {
        listingFee = _listingFee;
        platformFeeBps = _platformFeeBps;
    }

    function listNft(address _nftAddress, uint256 _tokenId, uint256 _price) external payable {
        if (msg.value != listingFee) revert ListingFeeInvalid();
        if (_price == 0) revert PriceMustBeAboveZero();

        IERC721 nft = IERC721(_nftAddress);
        if (nft.ownerOf(_tokenId) != msg.sender) revert NotOwner();

        if (!nft.isApprovedForAll(msg.sender, address(this)) && nft.getApproved(_tokenId) != address(this)) {
            revert NotApprovedForMarketplace();
        }

        listings[_nftAddress][_tokenId] = Listing({
            seller: msg.sender,
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            price: _price
        });

        if (listingFee > 0) {
            (bool success, ) = owner().call{value: listingFee}("");
            if (!success) revert FeeTransferFailed();
        }

        emit NFTListed(msg.sender, _nftAddress, _tokenId, _price);
    }

    function buyNft(address _nftAddress, uint256 _tokenId) external payable nonReentrant {
        Listing memory listedItem = listings[_nftAddress][_tokenId];
        
        if (listedItem.price == 0) revert ItemNotListed();
        if (msg.value != listedItem.price) revert PriceMismatch(listedItem.price, msg.value);
        if (listedItem.seller == msg.sender) revert SellerCannotBeBuyer();

        delete listings[_nftAddress][_tokenId];

        IERC721(_nftAddress).safeTransferFrom(listedItem.seller, msg.sender, _tokenId);

        uint256 platformFee = (listedItem.price * platformFeeBps) / MAX_BPS;
        uint256 sellerAmount = listedItem.price - platformFee;

        (bool successSeller, ) = listedItem.seller.call{value: sellerAmount}("");
        if (!successSeller) revert FeeTransferFailed();

        if (platformFee > 0) {
            (bool successOwner, ) = owner().call{value: platformFee}("");
            if (!successOwner) revert FeeTransferFailed();
        }

        emit NFTBought(
            msg.sender,
            listedItem.seller,
            _nftAddress,
            _tokenId,
            listedItem.price
        );
    }

    function cancelList(address _nftAddress, uint256 _tokenId) external {
        Listing memory listedItem = listings[_nftAddress][_tokenId];
        if (listedItem.seller != msg.sender) revert NotOwner();
        
        delete listings[_nftAddress][_tokenId];
        
        emit NFTCancelled(msg.sender, _nftAddress, _tokenId);
    }

    function setListingFee(uint256 _newFee) external onlyOwner {
        listingFee = _newFee;
        emit ListingFeeUpdated(_newFee);
    }

    function setPlatformFee(uint256 _newBps) external onlyOwner {
        if (_newBps > MAX_BPS) revert FeeTooHigh();
        platformFeeBps = _newBps;
        emit PlatformFeeUpdated(_newBps);
    }
}