// Filled in after deploy. Page uses CHAIN to pick which deployment to talk to.
export const CHAIN = 56; // 56 = BNB Chain mainnet, 97 = testnet

export const DEPLOYMENTS = {
  56: {
    name: "BNB Smart Chain",
    rpc: "https://bsc-dataseed.bnbchain.org",
    explorer: "https://bscscan.com",
    agentId: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F",
    jobs: "0xd8488651501763Ab4e51A0Be139b1E470B4e8Eb4",
    reputation: "0xDB026C5EF668c27E5Fd100cdB5a3Fa992371aB51",
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
