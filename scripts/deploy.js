// This is a script for deploying your contracts. You can adapt it to deploy
// yours, or create new ones.
async function main() {
  // This is just a convenience check
  if (network.name === "hardhat") {
    console.warn(
      "You are trying to deploy a contract to the Hardhat Network, which" +
        "gets automatically created and destroyed every time. Use the Hardhat" +
        " option '--network localhost'"
    );
  }

  const [deployer] = await ethers.getSigners();
  console.log(
    "Deploying the contracts with the account:",
    await deployer.getAddress()
  );
  console.log("Account balance:", (await deployer.getBalance()).toString());
  const usdcaddress = "0x2f3A40A3db8a7e3D09B0adfEfbCe4f6F81927557";
  const Token = await ethers.getContractFactory("MCC");
  const token = await Token.deploy(
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
    usdcaddress
  );
  await token.deployed();
  console.log("MCC:", token.address);

  await token.setCanBuy(true);
  await token.setPrice(10000000000000, 100, 10);
  await token.setDuration(86400);
  await token.setMaxBuyAmountPerTx(10000000000000000000000n);
  await token.setAddress(
    "0x0AE7AbAa1e3276784A87FcDDBD7A36949E97Dc25",
    "0x0AE7AbAa1e3276784A87FcDDBD7A36949E97Dc25",
    "0x0AE7AbAa1e3276784A87FcDDBD7A36949E97Dc25"
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
