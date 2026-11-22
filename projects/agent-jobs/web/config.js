// Filled in after deploy. Page uses CHAIN to pick which deployment to talk to.
export const CHAIN = 97; // 56 = BNB Chain mainnet, 97 = testnet

export const DEPLOYMENTS = {
  56: {
    name: "BNB Smart Chain",
    rpc: "https://bsc-dataseed.bnbchain.org",
    explorer: "https://bscscan.com",
    agentId: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F",
    jobs: "",
    reputation: "",
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
