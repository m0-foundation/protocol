import sys
import math
from eth_abi import encode

# python exp.py 
# 2.718...

x = float(sys.argv[1])
y = math.exp(x / 1e4) * 1e12

# print(f"x = {x}")
# print(f"y = {int(y)}")

# Debug
# print(y)

# Check y < 2**64
# assert y < 2**64, f"x = {x}"
# y = y * 1e18
#print(f"y = {y}")

# Encode
y = "0x" + encode(["uint128"], [int(y)]).hex()
print(y)
