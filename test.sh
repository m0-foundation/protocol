#!/usr/bin/env bash
set -e

gas=false
verbose=false

while getopts d:g:p:t:v flag; do
	case "${flag}" in
	d) directory=${OPTARG} ;;
	g) gas=true ;;
	p) profile=${OPTARG} ;;
	t) test=${OPTARG} ;;
	v) verbose=true ;;
	esac
done

export FOUNDRY_PROFILE=$profile
echo Using profile: $FOUNDRY_PROFILE
echo Higher verbosity: $verbose
echo Gas report: $gas
echo Test Match pattern: $test

if [ "$verbose" = false ]; then
	verbosity="-vv"
else
	verbosity="-vvvv"
fi

if [ -z "$test" ]; then
	if [ -z "$directory" ]; then
		forge test --match-path "test/*" $gasReport
	else
		forge test --match-path "$directory/*.t.sol" $gasReport
	fi
else
	forge test --match-test "$test" $gasReport $verbosity
fi
