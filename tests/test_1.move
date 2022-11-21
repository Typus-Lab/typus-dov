// #[test_only]
// module typus_dov::vault_tests {

//     #[test]
//     /// new vault
//     fun test_new_vault() {
//         use sui::test_scenario;
//         use sui::sui::SUI;

//         let admin = @0xBABE;
//         let scenario_val = test_scenario::begin(admin);
//         let scenario = &mut scenario_val;
//         {
//             // init(test_scenario::ctx(scenario));
//             let ctx = test_scenario::ctx(scenario);
//             let id = object::new(ctx);
//             emit(RegistryCreated { id: object::uid_to_inner(&id) });
//             transfer::transfer(ManagerCap { id: object::new(ctx) }, tx_context::sender(ctx));
//             transfer::share_object(VaultRegistry {
//                 id,
//                 num_of_vault: 0
//             })
//         };

//         test_scenario::next_tx(scenario, admin);
//         {
//             let registry = test_scenario::take_shared<VaultRegistry>(scenario);
//             new_vault<SUI>(
//                 &mut registry,
//                 1,
//                 1,
//                 1,
//                 true,
//                 1,
//                 2,
//                 test_scenario::ctx(scenario)
//             );
//             test_scenario::return_shared(registry)
//         };

//         test_scenario::end(scenario_val);
//     }
// }