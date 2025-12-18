// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract NFTMarketplace is Ownable {

    struct Listing{
        address seller;
        address nftAddress;
        uint256 tokenId;
        uint256 price;
    }

    mapping(address => mapping(uint256 => Listing)) listing;
    uint256 counter = 0;

    constructor () Ownable(msg.sender) {
        
    }

    function listNFT(address _nftAddress, uint256 _tokenId, uint256 _price) external{
        Listing memory newListing = Listing({
            seller: msg.sender,
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            price: _price
        });

        listing[_nftAddress][_tokenId] = newListing;
        counter++;
    }

}