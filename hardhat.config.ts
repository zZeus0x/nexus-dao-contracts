import "dotenv/config"
import "@nomiclabs/hardhat-ethers"
import "@nomiclabs/hardhat-etherscan"
import { HardhatUserConfig } from "hardhat/config"
import { existsSync } from "fs"

if (!existsSync("./.env")) {
  throw new Error(".env file doesn't exist")
}

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      gasPrice: 225000000000,
      chainId: 31337,
      forking:
        process.env.USE_LOCAL_TESTNET == "1"
          ? {
              url: "https://api.avax.network/ext/bc/C/rpc"
            }
          : undefined
    },
    mainnet: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      gasPrice: 225000000000,
      chainId: 43114,
      accounts: { mnemonic: process.env.MNEMONIC }
    }
  },

  etherscan: {
    apiKey: process.env.SNOWTRACE_API_KEY
  },

  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  }
}

export default config
