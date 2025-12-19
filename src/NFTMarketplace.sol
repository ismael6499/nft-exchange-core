// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract NFTMarketplace is Ownable, ReentrancyGuard {
    struct Listing {
        address seller;
        address nftAddress;
        uint256 tokenId;
        uint256 price;
    }

    mapping(address => mapping(uint256 => Listing)) listing;
    uint256 public listingFee;
    uint256 public saleFeePercent; // In basis points (e.g., 250 = 2.5%)
    uint256 private constant BASIS_POINTS = 10000;

    event NFTListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );
    event NFTBought(
        address indexed buyer,
        address seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );
    event NFTCancelled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );
    event ListingFeeUpdated(uint256 newFee);
    event SaleFeePercentUpdated(uint256 newPercent);

    constructor() Ownable(msg.sender) {}

    function listNFT(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _price
    ) external payable {
        require(msg.value == listingFee, "Incorrect listing fee");
        require(_price > 0, "Price cannot be 0");
        address _owner = IERC721(_nftAddress).ownerOf(_tokenId);
        require(_owner == msg.sender, "You aren't the NFT's owner");
        Listing memory newListing = Listing({
            seller: msg.sender,
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            price: _price
        });

        listing[_nftAddress][_tokenId] = newListing;

        if (listingFee > 0) {
            (bool success, ) = owner().call{value: listingFee}("");
            require(success, "Transfer of listing fee failed");
        }

        emit NFTListed(msg.sender, _nftAddress, _tokenId, _price);
    }

    function buyNFT(address _nftAddress, uint256 _tokenId) external payable {
        Listing memory currentList = listing[_nftAddress][_tokenId];
        require(currentList.price > 0, "NFT not listed");
        require(msg.value == currentList.price, "Not enough ETH");
        address _seller = currentList.seller;
        require(_seller != msg.sender, "You are the NFT's owner");
        delete listing[_nftAddress][_tokenId];

        IERC721(_nftAddress).safeTransferFrom(_seller, msg.sender, _tokenId);

        uint256 saleFee = (currentList.price * saleFeePercent) / BASIS_POINTS;
        uint256 sellerAmount = currentList.price - saleFee;

        (bool successSeller, ) = _seller.call{value: sellerAmount}("");
        require(successSeller, "Transfer to seller failed");

        if (saleFee > 0) {
            (bool successOwner, ) = owner().call{value: saleFee}("");
            require(successOwner, "Transfer of sale fee failed");
        }

        emit NFTBought(
            msg.sender,
            _seller,
            _nftAddress,
            _tokenId,
            currentList.price
        );
    }

    function cancelList(address _nftAddress, uint256 _tokenId) external {
        Listing memory currentListing = listing[_nftAddress][_tokenId];
        address _seller = currentListing.seller;
        require(_seller == msg.sender, "You aren't the NFT's owner");
        delete listing[_nftAddress][_tokenId];
        emit NFTCancelled(msg.sender, _nftAddress, _tokenId);
    }

    function setListingFee(uint256 _newFee) external onlyOwner {
        listingFee = _newFee;
        emit ListingFeeUpdated(_newFee);
    }

    function setSaleFeePercent(uint256 _newPercent) external onlyOwner {
        require(_newPercent <= BASIS_POINTS, "Percent cannot exceed 100%");
        saleFeePercent = _newPercent;
        emit SaleFeePercentUpdated(_newPercent);
    }
}
