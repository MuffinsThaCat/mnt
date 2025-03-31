// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title IBurnableToken
 * @dev Interface for tokens with burn functions
 */
interface IBurnableToken is IERC20 {
    function burn(uint256 amount) external;
}

/**
 * @title ILFJRouter
 * @dev Generic interface for Trader Joe V2.2 LBRouter
 */
interface ILFJRouter {
    function swapExactAVAXForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    
    function getAmountsOut(
        uint256 amountIn, 
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
    
    function WAVAX() external pure returns (address);
}

/**
 * @title RoyaltyProcessor
 * @dev Contract that receives royalty payments and uses them to buy and burn tokens
 */
contract RoyaltyProcessor is Ownable, ReentrancyGuard {
    // Burn Token Properties
    IERC20 public tokenToBurn;
    address public tokenToBurnAddress;
    bool public tokenHasBurnFunction;
    
    // Avalanche DEX Router Interfaces
    ILFJRouter public primaryRouter;
    ILFJRouter public secondaryRouter;
    address public WAVAX;
    
    // Minimum amount of tokens to receive when swapping (anti-slippage)
    uint256 public minTokensToReceive;
    
    // DEX preference for swaps
    enum DEX { PRIMARY, SECONDARY }
    DEX public preferredDEX;
    
    // NFT Contract that created this processor
    address public nftContract;
    
    // Events
    event TokensBurned(uint256 amountBurned);
    event MinTokensToReceiveUpdated(uint256 newMinAmount);
    event PreferredDEXUpdated(DEX newPreferredDEX);
    event RoyaltyReceived(address from, uint256 amount);
    
    constructor(
        address _tokenToBurnAddress,
        address _primaryRouterAddress,
        address _secondaryRouterAddress,
        bool _tokenHasBurnFunction,
        address _nftContract
    ) Ownable(msg.sender) {
        tokenToBurnAddress = _tokenToBurnAddress;
        tokenToBurn = IERC20(_tokenToBurnAddress);
        tokenHasBurnFunction = _tokenHasBurnFunction;
        
        // Initialize Avalanche DEX routers
        primaryRouter = ILFJRouter(_primaryRouterAddress);
        secondaryRouter = ILFJRouter(_secondaryRouterAddress);
        WAVAX = primaryRouter.WAVAX();
        
        // Set min tokens to receive to a reasonable default
        minTokensToReceive = 1;
        
        // Set primary DEX as default
        preferredDEX = DEX.PRIMARY;
        
        // Set the NFT contract
        nftContract = _nftContract;
    }
    
    /**
     * @dev Called when royalty is received
     * This is implicitly called via the receive function
     */
    function processRoyalty() internal nonReentrant {
        uint256 amount = address(this).balance;
        require(amount > 0, "No AVAX to process");
        
        emit RoyaltyReceived(msg.sender, amount);
        
        // Buy and burn tokens with the royalty
        _buyAndBurnTokens(amount);
    }
    
    /**
     * @dev Buys tokens on Avalanche DEX and burns them
     * @param amount Amount of AVAX to use for buying tokens
     */
    function _buyAndBurnTokens(uint256 amount) internal {
        // Create swap path from AVAX to token
        address[] memory path = new address[](2);
        path[0] = WAVAX;
        path[1] = tokenToBurnAddress;
        
        // Use price quotation from preferred DEX
        uint256 expectedOut;
        if (preferredDEX == DEX.PRIMARY) {
            expectedOut = primaryRouter.getAmountsOut(amount, path)[1];
        } else {
            expectedOut = secondaryRouter.getAmountsOut(amount, path)[1];
        }
        
        // Set minimum tokens to 95% of expected (5% slippage tolerance)
        uint256 minOut = (expectedOut * 95) / 100;
        
        // Use either calculated minimum or stored minimum, whichever is lower
        if (minOut > minTokensToReceive) {
            minOut = minTokensToReceive;
        }
        
        uint256[] memory received;
        
        // Try preferred DEX first
        try this._executeDEXSwap(preferredDEX, amount, minOut, path) returns (uint256[] memory result) {
            received = result;
        } catch {
            // If preferred DEX fails, try the other one
            DEX fallbackDEX = preferredDEX == DEX.PRIMARY ? DEX.SECONDARY : DEX.PRIMARY;
            received = this._executeDEXSwap(fallbackDEX, amount, minOut, path);
        }
        
        // Update min tokens to receive for future swaps (dynamic adjustment)
        // Set to 90% of what we received this time
        uint256 newMinTokens = (received[1] * 90) / 100;
        if (newMinTokens > 0 && newMinTokens != minTokensToReceive) {
            minTokensToReceive = newMinTokens;
            emit MinTokensToReceiveUpdated(newMinTokens);
        }
        
        // Burn all tokens received
        uint256 tokenBalance = tokenToBurn.balanceOf(address(this));
        require(tokenBalance > 0, "No tokens to burn");
        
        // Use burn function if available, otherwise send to dead address
        if (tokenHasBurnFunction) {
            IBurnableToken(tokenToBurnAddress).burn(tokenBalance);
        } else {
            // For tokens without burn function, transfer to dead address
            tokenToBurn.transfer(address(0xdead), tokenBalance);
        }
        
        emit TokensBurned(tokenBalance);
    }
    
    /**
     * @dev Helper function to execute a swap on a specific DEX
     * Using external call to handle exceptions appropriately
     */
    function _executeDEXSwap(
        DEX dex, 
        uint256 amount, 
        uint256 minOut, 
        address[] memory path
    ) external payable returns (uint256[] memory) {
        require(msg.sender == address(this), "External calls not allowed");
        
        if (dex == DEX.PRIMARY) {
            return primaryRouter.swapExactAVAXForTokens{value: amount}(
                minOut,
                path,
                address(this),
                block.timestamp + 300
            );
        } else {
            return secondaryRouter.swapExactAVAXForTokens{value: amount}(
                minOut,
                path,
                address(this),
                block.timestamp + 300
            );
        }
    }
    
    /**
     * @dev Check which DEX offers better token pricing for a given amount
     * Returns the DEX that gives better pricing and the expected output amount
     */
    function getBestDEXPricing(uint256 amount) public view returns (DEX bestDEX, uint256 expectedOutput) {
        address[] memory path = new address[](2);
        path[0] = WAVAX;
        path[1] = tokenToBurnAddress;
        
        uint256 primaryOutput = primaryRouter.getAmountsOut(amount, path)[1];
        uint256 secondaryOutput = secondaryRouter.getAmountsOut(amount, path)[1];
        
        if (primaryOutput >= secondaryOutput) {
            return (DEX.PRIMARY, primaryOutput);
        } else {
            return (DEX.SECONDARY, secondaryOutput);
        }
    }
    
    /**
     * @dev Auto-optimize preferred DEX based on current market pricing
     * Can be triggered by anyone but typically would be called by NFT contract
     */
    function optimizePreferredDEX() external {
        // Use a small amount for testing
        uint256 testAmount = 0.01 ether;
        (DEX bestDEX, ) = getBestDEXPricing(testAmount);
        if (bestDEX != preferredDEX) {
            preferredDEX = bestDEX;
            emit PreferredDEXUpdated(bestDEX);
        }
    }
    
    /**
     * @dev Owner can set preferred DEX
     */
    function setPreferredDEX(DEX _preferredDEX) external onlyOwner {
        preferredDEX = _preferredDEX;
        emit PreferredDEXUpdated(_preferredDEX);
    }
    
    /**
     * @dev Owner can update token has burn function flag
     */
    function setTokenHasBurnFunction(bool _tokenHasBurnFunction) external onlyOwner {
        tokenHasBurnFunction = _tokenHasBurnFunction;
    }
    
    /**
     * @dev Owner can update minimum tokens to receive
     */
    function setMinTokensToReceive(uint256 _minTokensToReceive) external onlyOwner {
        minTokensToReceive = _minTokensToReceive;
        emit MinTokensToReceiveUpdated(_minTokensToReceive);
    }
    
    /**
     * @dev Emergency function to recover stuck funds
     * Only owner can call this (which should be the NFT contract)
     */
    function recoverFunds() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner()).call{value: balance}("");
            require(success, "Transfer failed");
        }
    }
    
    /**
     * @dev Emergency function to rescue tokens sent to this contract
     */
    function rescueTokens(address tokenAddress) external onlyOwner {
        // Don't allow rescuing the burn token to prevent abuse
        require(tokenAddress != tokenToBurnAddress, "Cannot rescue burn token");
        
        IERC20 token = IERC20(tokenAddress);
        uint256 amount = token.balanceOf(address(this));
        require(amount > 0, "No tokens to rescue");
        token.transfer(owner(), amount);
    }
    
    /**
     * @dev Receive function to handle royalty payments
     * This is called when AVAX is sent to this contract
     */
    receive() external payable {
        // Process payments only if they're substantial enough
        // This prevents dust attacks and saves gas when tiny amounts are received
        if (msg.value >= 0.001 ether) {
            // Always process payments that come from the NFT contract or owner
            if (msg.sender == nftContract || msg.sender == owner()) {
                processRoyalty();
            } else {
                // For unknown sources (like marketplaces), accumulate and let owner 
                // trigger processing manually, or automatically process larger amounts
                if (msg.value >= 0.1 ether) {
                    // Auto-process larger payments (likely royalties)
                    processRoyalty();
                }
                // Otherwise, funds will be held for manual processing
            }
        }
    }
    
    /**
     * @dev Allow manual processing of accumulated royalties from marketplaces
     * Useful when marketplaces send royalties directly but in smaller amounts
     */
    function manuallyProcessRoyalties() external {
        require(
            msg.sender == nftContract || msg.sender == owner(),
            "Only NFT contract or owner can trigger processing"
        );
        
        uint256 balance = address(this).balance;
        require(balance >= 0.001 ether, "Insufficient balance to process");
        
        processRoyalty();
    }
}
