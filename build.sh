#!/usr/bin/env bash
set -e

sizes=false

while getopts p:s flag
do
    case "${flag}" in
        p) profile=${OPTARG};;
        s) sizes=true;;
    esac
done

export FOUNDRY_PROFILE=$profile
echo Using profile: $FOUNDRY_PROFILE

if [ "$sizes" = false ];
then
    forge build --skip '*/test/**/*.sol' --skip '*/script/**' --skip '*/lib/forge-std/**' --extra-output-files abi;
else
    forge build --skip '*/test/**/*.sol' --skip '*/script/**' --skip '*/lib/forge-std/**' --extra-output-files abi --sizes;
fi
