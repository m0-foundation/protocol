# coverage report
coverage :; forge coverage --report lcov && lcov --remove ./lcov.info -o ./lcov.info 'script/*' 'test/*' && genhtml lcov.info --branch-coverage --output-dir coverage

coverage-summary :; forge coverage --report summary

# Deployment helpers

deploy-local :; FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --rpc-url localhost --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast -v

deploy-sepolia :; FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --rpc-url sepolia --private-key ${ETH_PK} --broadcast -vvv

deploy-qa-sepolia :; FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --rpc-url sepolia --broadcast -v

# Run slither
slither :; FOUNDRY_PROFILE=production forge build --build-info --skip '*/test/**' --skip '*/script/**' --force && slither --compile-force-framework foundry --ignore-compile --sarif results.sarif --config-file slither.config.json .

profile ?=default

build:
	@./build.sh -p production

test:
	@./test.sh -p $(profile)

fuzz:
	@./test.sh -t testFuzz -p $(profile)

integration:
	@./test.sh -d test/integration -p $(profile)

invariant:
	@./test.sh -d test/invariant -p $(profile)

gas-report:
	forge test --no-match-path 'test/invariant/*' --gas-report > gasreport.ansi

gas-report-hardhat:
	npx hardhat test

sizes:
	@./build.sh -p production -s

clean:
	forge clean
