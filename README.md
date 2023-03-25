# Typus DeFi Option Vaults (DOV)

## Vault
[README](typus_framework/README.md)

## Covered Call
[README](covered_call/README.md)

## Deployment Manual
1. deploy [sui-dev-token](https://github.com/Typus-Lab/sui-dev-token)
2. update [sui-dev-token README.md](https://github.com/Typus-Lab/sui-dev-token/blob/main/README.md) addresses
3. deploy [typus-oracle](https://github.com/Typus-Lab/typus-oracle)
4. update [typus-oracle Move.toml](https://github.com/Typus-Lab/typus-oracle/blob/main/Move.toml) `typus_oracle` address
5. send `new_time`, `new_oracle` transactions
   ```c
   sui client call --gas-budget 10000 --package $TYPUS_ORACLE_ADDRESS --module "unix_time" --function "new_time"
   ```
   ```c
   sui client call --gas-budget 10000 --package $TYPUS_ORACLE --module "oracle" --function "new_oracle" --type-args $BTC_CONTRACT_ADDRESS::btc::BTC --args 8
   ```
6. update [typus-cranker](https://github.com/Typus-Lab/typus-rust)
7. update [typus-oracle README.md](https://github.com/Typus-Lab/typus-oracle/blob/main/README.md) addresses
8. deploy [typus_framework](https://github.com/Typus-Lab/typus-dov/tree/main/typus_framework)
9. update [typus_framework Move.toml](https://github.com/Typus-Lab/typus-dov/blob/main/typus_framework/Move.toml) `typus_framework` address
10. update [typus_framework README.md](https://github.com/Typus-Lab/typus-dov/blob/main/typus_framework/README.md) addresses
11. deploy [covered_call](https://github.com/Typus-Lab/typus-dov/tree/main/covered_call)
12. update [covered_call README.md](https://github.com/Typus-Lab/typus-dov/blob/main/covered_call/README.md) addresses
13. send `new_covered_call_vault` transaction
    ```c
    sui client call --package $COVERED_CALL_PACKAGE_ADDRESS --module covered_call --function new_covered_call_vault --type-args 0x2::sui::SUI --args $COVERED_CALL_MANAGER_CAP_ADDRESS $COVERED_CALL_REGISTRY_ADDRESS 1672531200000 2000 --gas-budget 10000
    ```