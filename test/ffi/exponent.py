import sys
import math
from eth_abi import encode

# python exponent.py 
# 2.718...

x = float(sys.argv[1])
y = math.exp(x / 1e4) * 1e12

# Debug
# print(f"x = {x}")
# print(f"y = {int(y)}")

# Encode
y = "0x" + encode(["uint128"], [int(y)]).hex()
print(y)
