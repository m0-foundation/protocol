# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

profile ?=default

# Coverage report
coverage:
	FOUNDRY_PROFILE=$(profile) forge coverage --no-match-path 'test/invariant/**/*.sol' --report lcov && lcov --extract lcov.info -o lcov.info 'src/*' && genhtml lcov.info -o coverage

coverage-summary:
	FOUNDRY_PROFILE=$(profile) forge coverage --no-match-path 'test/invariant/**/*.sol' --report summary

# Deployment helpers
deploy:
	FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --skip src --skip test --rpc-url mainnet --slow --broadcast -vvv

deploy-sepolia:
	FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --skip src --skip test --rpc-url sepolia --slow --broadcast -vvv

deploy-local:
	FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --skip src --skip test --rpc-url localhost --slow --broadcast -v

# Run slither
slither:
	FOUNDRY_PROFILE=production forge build --build-info --skip '*/test/**' --skip '*/script/**' --force && slither --compile-force-framework foundry --ignore-compile --sarif results.sarif --config-file slither.config.json .


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
	FOUNDRY_PROFILE=$(profile) forge test --no-match-path 'test/invariant/*' --gas-report > gasreport.ansi

gas-report-hardhat:
	npx hardhat test

sizes:
	@./build.sh -p production -s

clean:
	forge clean
