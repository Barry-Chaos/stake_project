const { ethers, upgrades } = require("hardhat");

async function main() {
    const RCCStake = await ethers.getContractFactory("RCCStake"); // 0x5107E77393a9dc858Adb85A7fC7541f7Db651c4A

    const proxy = await upgrades.deployProxy(
        RCCStake, 
        ['0x48b0eb5edc42119206c77c92daef0923325bb783', 1, 7000000, 1000], 
        { initializer: "initialize" }
    );
    await proxy.waitForDeployment();
    console.log("RCCStake proxy deployed to:", proxy.target); // 0x7C06F9aAdD9206506D5E645d1979e034a6da8e85
}

main();