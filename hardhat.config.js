require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config(); 
require('@openzeppelin/hardhat-upgrades');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.24",
  networks: {
    hardhat: {},
    sepolia: {
      url: "https://sepolia.infura.io/v3/" + process.env.INFURA_API_KEY, accounts: [`0x${process.env.PRIVATE_KEY}`],
    },
  },
};
