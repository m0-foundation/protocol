# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# Coverage report

coverage:
	forge coverage --report lcov && lcov --remove ./lcov.info -o ./lcov.info 'script/*' 'test/*' && genhtml lcov.info --branch-coverage --output-dir coverage

coverage-summary:
	forge coverage --report summary

# Deployment helpers

deploy:
	FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --skip src --skip test --rpc-url mainnet --broadcast -vvv

deploy-sepolia:
	FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --skip src --skip test --rpc-url sepolia --broadcast -vvv

deploy-local:
	FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --skip src --skip test --rpc-url localhost --broadcast -v

# Run slither
slither:
	FOUNDRY_PROFILE=production forge build --build-info --skip '*/test/**' --skip '*/script/**' --force && slither --compile-force-framework foundry --ignore-compile --sarif results.sarif --config-file slither.config.json .

profile ?=default

# Common tasks

update:
	forge update

build:
	@./build.sh -p production

tests:
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
