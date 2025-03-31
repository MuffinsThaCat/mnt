# NFT with Royalty-Based Token Burning

A Solidity-based NFT contract system for the Avalanche network that automatically buys and burns $Booty tokens using royalties from secondary NFT sales.

## Features

- Standard ERC721 NFT implementation with minting functionality
- ERC2981 royalty support (compatible with major NFT marketplaces)
- Automatic buying and burning of $Booty tokens from royalty proceeds
- Dynamic DEX routing between Trader Joe and Pharaoh for best token pricing
- Secure implementation with reentrancy protection and proper access controls

## Contract Architecture

The system consists of two main contracts:

1. **NFTWithRoyaltyBurn.sol** - The main NFT contract that handles minting and royalty routing
2. **RoyaltyProcessor.sol** - A specialized contract that receives royalties and converts them to $Booty tokens for burning

## Configured Addresses

- **$Booty Token**: `0x4A5Bb433132B7E7F75D6A9a3e4136bB85CE6E4d5`
- **Trader Joe V2.2 LBRouter**: `0x18556DA13313f3532c54711497A8FedAC273220E`
- **Pharaoh SwapRouter**: `0x062c62cA66E50Cfe277A95564Fe5bB504db1Fab8`

## How It Works

1. When NFTs are sold on secondary marketplaces, royalties (10% by default) are sent to the RoyaltyProcessor contract
2. The processor automatically buys $Booty tokens with the royalty payments
3. These tokens are then burned (sent to a dead address), creating deflationary pressure
4. The system automatically chooses between Trader Joe and Pharaoh exchanges to get the best price

## Deployment Process

```
npm install
npx hardhat compile
npx hardhat run scripts/deploy.js --network avalanche
```

## Marketplace Compatibility

This system works best with NFT marketplaces that support the ERC2981 royalty standard, including:

- NFTrade
- Kalao
- Joepegs

## Requirements

- Node.js v14+
- Hardhat
- OpenZeppelin Contracts
- Access to Avalanche RPC

## License

MIT