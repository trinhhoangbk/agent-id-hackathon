// Filled in after deploy. Page uses CHAIN to pick which deployment to talk to.
export const CHAIN = 56; // 56 = BNB Chain mainnet, 97 = testnet

export const DEPLOYMENTS = {
  56: {
    name: "BNB Smart Chain",
    rpc: "https://bsc-dataseed.bnbchain.org",
    explorer: "https://bscscan.com",
    agentId: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F",
    jobs: "0x90c61296F20edDF284F5c2944EE102328F71a437",
    reputation: "0x963E45D63BF80dF2B01794F1F877902AA67af227",
  },
  97: {
    name: "BNB Smart Chain Testnet",
    rpc: "https://bsc-testnet-rpc.publicnode.com",
    explorer: "https://testnet.bscscan.com",
    agentId: "",
    jobs: "",
    reputation: "",
  },
};
