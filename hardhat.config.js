require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-vyper");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-gas-reporter");
require("hardhat-dependency-compiler");
require("hardhat-contract-sizer");
require("hardhat-change-network");
require("solidity-coverage");

require('dotenv').config();
const fs = require("fs");
const inputConfig = require(process.env.HHC_PASS ? process.env.HHC_PASS : './input_config.json');
const outputConfig = require(process.env.HHC_PASS ? process.env.HHC_PASS : './output_config.json');

const PRIVATE_KEY_UNITED = process.env.PRIVATE_KEY || "0x0000000000000000000000000000000000000000";

task("balanceDeployer", "Print info about balance deployer", async () => {
  const [deployer] = await ethers.getSigners();
  const balance = await deployer.getBalance();
  console.log("Deployer balance: ", ethers.utils.formatEther(balance));

});
task("getBlockNum", "", async () => {
  console.log(`crutch=${await ethers.provider.getBlockNumber()}`);
});

//TODO: dynamic rpcUrl for gitlab snippet
task("updateHelper", "update field sourceForRepresentation depends on inbound list network for deploy. Note: only if helpler with empty sourceForRepresentation")
  .addParam("nets", "")
  .setAction(async (taskArgs) => {
    const inboundListNets = taskArgs.nets.split(",");
    //1. check if array in every net not empty then exit. reason: recently config was prepared (in ci: additional deploy)
    const intersectionResult = Object.keys(inputConfig).filter(x => inboundListNets.indexOf(x) !== -1).length;
    if (intersectionResult !== inboundListNets.length) { console.error('ERROR: Wrong inbound net name or helper file does\'t contains inbount net'); process.exit(1); }
    for (net in inputConfig) {
      if (!inputConfig[net].sourceForRepresentation || inputConfig[net].sourceForRepresentation.length > 0) {
        console.warn('WARNING: Preparing helper file stoped. The file was recently prepared! Are you in \"ci: additional deploy\" now ?')
        process.exit(0);
      }
    }
    //2. in every net does update the array
    inboundListNets.map(inboundNet => {
      let preparedListNets = inboundListNets.filter(delNet => delNet !== inboundNet);
      inputConfig[inboundNet].sourceForRepresentation = preparedListNets;
    })
    //3. save
    fs.writeFileSync(process.env.HHC_PASS ? process.env.HHC_PASS : "./input_config.json",
      JSON.stringify(inputConfig, undefined, 2));
  });


module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {

    },
    localhost: {
      //
    },
    polygon:{
      url: 'https://polygon.llamarpc.com',
      browserURL: "https://polygonscan.com",
      accounts: [PRIVATE_KEY_UNITED]
    },
    bsc: {
      url: 'https://bsc-dataseed1.binance.org',
      browserURL: "https://bscscan.com",
      accounts: [PRIVATE_KEY_UNITED]
    },
    avalanche:{
      url: 'https://avalanche.public-rpc.com',
      browserURL: "https://snowtrace.io",
      accounts: [PRIVATE_KEY_UNITED]
    },
    ethereum: {
      url: 'https://ethereum.publicnode.com',
      browserURL: "https://etherscan.io",
      accounts: [PRIVATE_KEY_UNITED]
    },
     bsctestnet: {
       url: "https://data-seed-prebsc-2-s3.binance.org:8545",
       browserURL: "https://testnet.bscscan.com",
       accounts: [PRIVATE_KEY_UNITED]
     },
     ftmTestnet: {
      url: 'https://rpc.ankr.com/fantom_testnet',
      accounts: [PRIVATE_KEY_UNITED]
     },
    fantom:{
      url: 'https://rpcapi.fantom.network',
      browserURL: "https://ftmscan.com",
      accounts: [PRIVATE_KEY_UNITED]
    },
    arbitrum:{
      url: 'https://arb1.croswap.com/rpc',
      accounts: [PRIVATE_KEY_UNITED],
      browserURL: "https://arbiscan.io"
    },
    network1: {
       url: "http://172.20.128.11:7545",
       accounts: [PRIVATE_KEY_UNITED]
    },
    network2: {
       url: "http://172.20.128.12:8545",
       accounts: [PRIVATE_KEY_UNITED]
    },
    network3: {
       url: "http://172.20.128.13:9545",
       accounts: [PRIVATE_KEY_UNITED]
    }
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY,
      goerli: process.env.ETHERSCAN_API_KEY,
      bsc: process.env.BINANCESCAN_API_KEY,
      bscTestnet: process.env.BINANCESCAN_API_KEY,,
      polygon: process.env.POLYGONSCAN_API_KEY,
      polygonMumbai: process.env.POLYGONSCAN_API_KEY,
      avalanche: process.env.AVALANCHESCAN_API_KEY,
      avalancheFujiTestnet: process.env.AVALANCHESCAN_API_KEY,
      aurora: process.env.AURORA_API_KEY,
      auroraTestnet: process.env.AURORA_API_KEY,
      opera: process.env.FANTOM_API_KEY,
      ftmTestnet: process.env.FANTOM_API_KEY,
      arbitrumOne: process.env.ARBITRUM_API_KEY,
      arbitrumTestnet: process.env.ARBITRUM_API_KEY,

    }
  },
  gasReporter: {
    currency: "USD",
    gasPrice: 100,
    // enabled: process.env.REPORT_GAS ? true : false,
  },
  solidity: {
    compilers: [{
      version: "0.8.17",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }, {
      version: "0.7.6",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }, {
      version: "0.8.2",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }, {
      version: "0.4.24",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }, {
      version: "0.5.16",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }, {
      version: "0.6.6",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }, {
      version: "0.4.18",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }]
  },
  vyper: {
    compilers: [{ version: "0.2.4" }, { version: "0.2.7" }, { version: "0.2.8" }, { version: "0.3.1" }],
  },
  mocha: {
    timeout: 100000
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  dependencyCompiler: {
    paths: [
    ],
    keep: true,
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true
  },
  gasReporter: {
    enabled: true,
    currency: 'USD',
    gasPrice: 34,
    showTimeSpent: true,
    token: 'AVA',
    gasPriceApi: 'https://api.bscscan.com/api?module=proxy&action=eth_gasPrice'
  },
};
