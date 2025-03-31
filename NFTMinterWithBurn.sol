// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./RoyaltyProcessor.sol";

// Interfaces for Avalanche DEX interaction
interface ILFJRouter {
    function swapExactAVAXForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    
    function WAVAX() external pure returns (address);
}

interface IPharoahRouter {
    function swapExactAVAXForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    
    function WAVAX() external pure returns (address);
}

/**
 * @title NFTWithRoyaltyBurn
 * @dev ERC721 NFT that uses secondary sale royalties to buy and burn a token on Avalanche
 */
contract NFTWithRoyaltyBurn is ERC721, ERC721Enumerable, ERC721URIStorage, ERC2981, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // NFT Properties
    uint256 public maxSupply;
    uint256 public mintPrice;
    uint256 public totalSupply;
    string public baseURI;
    
    // Token to Burn Properties
    address public tokenToBurnAddress;
    bool public tokenHasBurnFunction;
    
    // Royalty processor for secondary sales
    RoyaltyProcessor public royaltyProcessor;
    
    // Events
    event NFTMinted(address to, uint256 tokenId);
    event RoyaltyProcessorDeployed(address processorAddress);
    
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        uint256 _mintPrice,
        string memory _baseURI,
        address _tokenToBurnAddress,
        address _lfjRouterAddress,
        address _pharoahRouterAddress,
        bool _tokenHasBurnFunction,
        address _royaltyReceiver,
        uint96 _royaltyFeeNumerator
    ) ERC721(_name, _symbol) Ownable(msg.sender) {
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        baseURI = _baseURI;
        tokenToBurnAddress = _tokenToBurnAddress;
        tokenHasBurnFunction = _tokenHasBurnFunction;
        
        // Set default royalty - this will be overridden once royalty processor is deployed
        _setDefaultRoyalty(_royaltyReceiver, _royaltyFeeNumerator);
        
        // Create royalty processor (will be deployed in a separate step after construction)
        // This is done to avoid circular dependencies
    }
    
    /**
     * @dev Initialize the royalty processor after contract deployment
     * This must be called after the contract is deployed
     */
    function initializeRoyaltyProcessor(
        address _lfjRouterAddress,
        address _pharoahRouterAddress
    ) external onlyOwner {
        require(address(royaltyProcessor) == address(0), "Royalty processor already initialized");
        
        // Deploy the royalty processor
        royaltyProcessor = new RoyaltyProcessor(
            tokenToBurnAddress,
            _lfjRouterAddress,
            _pharoahRouterAddress,
            tokenHasBurnFunction,
            address(this)
        );
        
        // Set the royalty processor as the royalty receiver
        // We'll use the same royalty percentage that was initially set in the constructor
        address currentReceiver;
        uint256 currentRoyaltyAmount;
        (currentReceiver, currentRoyaltyAmount) = royaltyInfo(1, 10000); // Get current royalty for a 10000 wei sale
        uint96 currentFeeNumerator = uint96(currentRoyaltyAmount); // Extract the fee numerator
        
        _setDefaultRoyalty(address(royaltyProcessor), currentFeeNumerator);
        
        emit RoyaltyProcessorDeployed(address(royaltyProcessor));
    }
    
    /**
     * @dev Mints a new NFT
     */
    function mint(address to) external payable nonReentrant {
        require(totalSupply < maxSupply, "Max supply reached");
        require(msg.value >= mintPrice, "Insufficient payment");
        
        // Mint NFT
        uint256 tokenId = totalSupply + 1;
        _safeMint(to, tokenId);
        totalSupply++;
        
        emit NFTMinted(to, tokenId);
        
        // Return excess payment
        uint256 excess = msg.value - mintPrice;
        if (excess > 0) {
            (bool success, ) = payable(msg.sender).call{value: excess}("");
            require(success, "Refund failed");
        }
    }
    
    /**
     * @dev Allow owner to manually trigger optimizing the DEX on the royalty processor
     */
    function optimizeRoyaltyProcessorDEX() external {
        require(address(royaltyProcessor) != address(0), "Royalty processor not initialized");
        royaltyProcessor.optimizePreferredDEX();
    }
    
    /**
     * @dev Forward any directly received royalties to the processor
     * This is a fallback in case marketplaces send royalties directly to this contract
     */
    function forwardRoyalties() external {
        require(address(royaltyProcessor) != address(0), "Royalty processor not initialized");
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(address(royaltyProcessor)).call{value: balance}("");
            require(success, "Forwarding failed");
        }
    }
    
    /**
     * @dev Owner can withdraw contract balance
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
    
    /**
     * @dev Owner can update mint price
     */
    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        mintPrice = _mintPrice;
    }
    
    /**
     * @dev Owner can update base URI
     */
    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }
    
    /**
     * @dev Owner can update royalty recipient and percentage
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }
    
    /**
     * @dev Emergency function to rescue tokens sent to this contract
     */
    function rescueTokens(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 amount = token.balanceOf(address(this));
        require(amount > 0, "No tokens to rescue");
        token.transfer(owner(), amount);
    }
    
    /**
     * @dev Receive function to handle direct AVAX transfers
     */
    receive() external payable {
        // Forward payments to royalty processor if it exists
        if (address(royaltyProcessor) != address(0) && msg.value > 0) {
            (bool success, ) = payable(address(royaltyProcessor)).call{value: msg.value}("");
            require(success, "Forwarding to processor failed");
        }
    }
    
    // The following functions are overrides required by Solidity
    
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return string(abi.encodePacked(baseURI, tokenId.toString()));
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
