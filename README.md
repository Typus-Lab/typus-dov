# Typus DeFi Option Vaults (DOV)

## Vault
[README](typus_dov/README.md)

## Covered Call
[README](covered_call/README.md)

## Deployment Manual
1. deploy [sui-dev-token](https://github.com/Typus-Lab/sui-dev-token)
2. update [sui-dev-token README.md](https://github.com/Typus-Lab/sui-dev-token/blob/main/README.md) addresses
3. deploy [typus-oracle](https://github.com/Typus-Lab/typus-oracle)
4. update [typus-oracle Move.toml](https://github.com/Typus-Lab/typus-oracle/blob/main/Move.toml) `typus_oracle` address
5. send `new_time`, `new_oracle` transactions
   ```cmd
   sui client call --gas-budget 10000 --package $PACKAGE --module "unix_time" --function "new_time"
   ```
6. update [typus-oracle README.md](https://github.com/Typus-Lab/typus-oracle/blob/main/README.md) addresses