-include .env

.PHONY: install build test test-fuzz coverage fmt deploy clean

install:
	forge install foundry-rs/forge-std --no-commit
	forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-commit

build:
	forge build

test:
	forge test -vv

test-fuzz:
	forge test --match-test testFuzz -vvv

test-invariant:
	forge test --match-path "test/fuzz/*" -vvv

coverage:
	forge coverage --report summary

gas:
	forge test --gas-report

fmt:
	forge fmt

deploy:
	forge script script/Deploy.s.sol:DeployPhase1 --rpc-url $(RPC_URL) --broadcast --verify

clean:
	forge clean
