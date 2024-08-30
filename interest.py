supplyUSDCDepositUser1 = 100000000
user3supplyusdc = 30000000
user4supplyusdc = 10000000

debt = 2000
for i in range(1501):
    debt = debt + (debt * 0.001)
    if i==1000:
        debt1000 = debt - 2000
debt = debt - 2000
# print(debt*user3supplyusdc/(supplyUSDCDepositUser1+user3supplyusdc))
print(debt-debt1000)
debt = debt-debt1000
print(debt*user4supplyusdc/(supplyUSDCDepositUser1+user3supplyusdc+user4supplyusdc))
