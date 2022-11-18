# Typus DeFi Option Vaults (DOV)

## Vault

`sui move build`
`sui client publish --gas-budget 10000`

output:

```
----- Transaction Effects ----
Status : Success
Created Objects:
- ID: 0x77c842dc3caf4cb639dd09fc875849d3705dcbb5 , Owner: Shared
- ID: 0x7e9e58daeb94bbd0450bb9ee9f00e219a1f2b734 , Owner: Immutable
- ID: 0xcf1dc245a7c32be995e9c46770033ccc38e4b1e6 , Owner: Account Address ( 0x4a3b00eac21bfbe062932a5c2b9710245edb2cc2 )
```

`export PACKAGE=0x7e9e58daeb94bbd0450bb9ee9f00e219a1f2b734`
`export VAULT_REGISTRY=0x77c842dc3caf4cb639dd09fc875849d3705dcbb5`

`sui client call --gas-budget 1000 --package $PACKAGE --module "vault" --function "new_vault" --type-args 0x2::sui::SUI --args $VAULT_REGISTRY 1671344789 1 100000 1 10`

`sui client call --gas-budget 1000 --package $PACKAGE --module "vault" --function "deposit" --type-args 0x2::sui::SUI --args $VAULT_REGISTRY 0 0x005fdc62fa8d1b61725e1d6afaa14dce27139f3f`
