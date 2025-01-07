const ethers = require("ethers");

async function increaseTime(seconds) {
    const provider = new ethers.JsonRpcProvider("http://127.0.0.1:8545");
    await provider.send("evm_increaseTime", [seconds]);
    await provider.send("evm_mine", []);
}

// Example: Increase time by 1 hour
increaseTime(480);
