-include .env

.PHONY: all test clean deploy help install snapshot format anvil 

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network goerli\""

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

coverage :; forge coverage --report debug > coverage-report.txt

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil --accounts 15 --timestamp 300000 --host 0.0.0.0 --block-time 1
anvil2:; anvil --accounts 15 --timestamp 300000 --host 0.0.0.0

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

ifeq ($(findstring --network goerli,$(ARGS)),--network goerli)
	NETWORK_ARGS := --rpc-url $(GOERLI_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

deploy-anchor:
	@forge script script/DeployAnchor.s.sol $(NETWORK_ARGS)

update-oracle:
	@forge script script/UpdateMockOracle.s.sol $(NETWORK_ARGS)

deposit-n-mint:
	@forge script script/DepositAndMint.s.sol $(NETWORK_ARGS)

deposit-n-mint-multiple-users:
	@forge script script/DepositAndMintMultipleUsers.s.sol $(NETWORK_ARGS)

register-providers:
	@forge script script/RegisterRedemptionProviders.s.sol $(NETWORK_ARGS)
accumulate-rewards:
	@forge script script/AccumulateStETHRewards.s.sol $(NETWORK_ARGS)
read:
	@forge script script/ReadAnchorEngine.s.sol $(NETWORK_ARGS)
harvest:
	@forge script script/HarvestYield.s.sol $(NETWORK_ARGS)
register-provider:
	@forge script script/RegisterProvider.s.sol $(NETWORK_ARGS)

setup: deploy-anchor deposit-n-mint-multiple-users register-providers

