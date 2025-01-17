const {ethers, upgrades} = require("hardhat");

async function main() {
    const BtfsAirdrop = await ethers.getContractFactory("BtfsAirdrop");

    console.log("Deploying BtfsAirdrop...");

    const btfsAirdrop = await upgrades.deployProxy(BtfsAirdrop, {
        kind: 'uups'
    });

    await btfsAirdrop.deployed();

    console.log("BtfsAirdrop deployed to:", btfsAirdrop.address);

    let addr = await btfsAirdrop.getImplementation();

    console.log("Implementation deployed to: ", addr)

}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });