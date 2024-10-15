// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("ERC20Module", (m) => {
  const erc20 = m.contract("ERC20", ["TestERC20", "TestERC20"]);
  return { erc20 }; // 0x48B0eb5EDc42119206c77c92DaeF0923325BB783
});
