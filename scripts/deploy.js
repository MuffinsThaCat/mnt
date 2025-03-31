const hre = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Configuration parameters
  const nftName = "MyAwesomeNFT";
  const nftSymbol = "MANFT";
  const maxSupply = 10000;
  const mintPrice = ethers.parseEther("0.05"); // 0.05 AVAX per mint
  const baseURI = "ipfs://YOUR_CID_HERE/";
  
  // $Booty token to burn
  const tokenToBurnAddress = "0x4A5Bb433132B7E7F75D6A9a3e4136bB85CE6E4d5"; 
  
  // Avalanche DEX router addresses
  const lfjRouterAddress = "0x18556DA13313f3532c54711497A8FedAC273220E"; // LFJ (Trader Joe) V2.2 LBRouter
  const pharoahRouterAddress = "0x062c62cA66E50Cfe277A95564Fe5bB504db1Fab8"; // Official verified Pharaoh SwapRouter
  
  // Whether the token has a burn() function or we should use transfer to dead address
  const tokenHasBurnFunction = false;
  
  // Royalty settings (10% royalty)
  const royaltyReceiver = deployer.address; // Initially set to deployer, will be changed to processor
  const royaltyFeeNumerator = 1000; // 10% (out of 10000)

  // Deploy the NFT contract
  const NFTWithRoyaltyBurn = await ethers.getContractFactory("NFTWithRoyaltyBurn");
  const nftContract = await NFTWithRoyaltyBurn.deploy(
    nftName,
    nftSymbol,
    maxSupply,
    mintPrice,
    baseURI,
    tokenToBurnAddress,
    lfjRouterAddress,
    pharoahRouterAddress,
    tokenHasBurnFunction,
    royaltyReceiver,
    royaltyFeeNumerator
  );

  await nftContract.waitForDeployment();
  console.log("NFTWithRoyaltyBurn deployed to:", await nftContract.getAddress());

  // Initialize the royalty processor
  const initTx = await nftContract.initializeRoyaltyProcessor(
    lfjRouterAddress,
    pharoahRouterAddress
  );
  
  await initTx.wait();
  console.log("Royalty processor initialized");
  
  // Get the address of the deployed royalty processor
  const royaltyProcessorAddress = await nftContract.royaltyProcessor();
  console.log("Royalty processor deployed to:", royaltyProcessorAddress);

  console.log("Contract parameters:");
  console.log("  Name:", nftName);
  console.log("  Symbol:", nftSymbol);
  console.log("  Max Supply:", maxSupply);
  console.log("  Mint Price:", ethers.formatEther(mintPrice), "AVAX");
  console.log("  Base URI:", baseURI);
  console.log("  Token to Burn ($Booty):", tokenToBurnAddress);
  console.log("  LFJ Router (Trader Joe V2.2):", lfjRouterAddress);
  console.log("  Pharoah Router:", pharoahRouterAddress);
  console.log("  Token Has Burn Function:", tokenHasBurnFunction);
  console.log("  Initial Royalty Receiver:", royaltyReceiver);
  console.log("  Royalty Fee:", royaltyFeeNumerator/100, "%");
  console.log("  Final Royalty Receiver:", royaltyProcessorAddress);
  console.log("  Burn Mechanism: Secondary sale royalties will buy and burn $Booty tokens");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
