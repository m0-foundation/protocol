#!/usr/bin/env bash
set -e

gas=false

while getopts gp:t: flag
do
    case "${flag}" in
        g) gas=true;;
        p) profile=${OPTARG};;
        t) test=${OPTARG};;
    esac
done

export FOUNDRY_PROFILE=$profile
echo Using profile: $FOUNDRY_PROFILE

if [ -z "$test" ];
then
    if [ "$gas" = false ];
    then
        forge test --match-path "test/*";
    else
        forge test --match-path "test/*" --gas-report;
    fi
else
    if [ "$gas" = false ];
    then
        forge test --match-test "$test" -vvvv;
    else
        forge test --match-test "$test" --gas-report -vvvv;
    fi
fi
