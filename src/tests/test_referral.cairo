use array::ArrayTrait;
use traits::{Into, TryInto};
use option::OptionTrait;
use starknet::testing;
use starknet::ContractAddress;
use referral::referral::{Referral, IReferralDispatcher, IReferralDispatcherTrait};
use super::constants::{OWNER, ZERO, OTHER, USER, REFERRAL_ADDR, USER_A, USER_B, USER_C};
use super::utils;
use super::mocks::erc20::{ERC20, IERC20Dispatcher, IERC20DispatcherTrait};
use identity::{identity::main::Identity};
use naming::{
    pricing::Pricing, naming::main::Naming,
    interface::naming::{INaming, INamingDispatcher, INamingDispatcherTrait}
};
use super::mocks::referral_v2::{Referral_V2, IReferral_V2Dispatcher, IReferral_V2DispatcherTrait};
use referral::upgrades::upgradeable::Upgradeable;

// 
// SETUP
// 

fn setup(
    min_claim_amount: u256, share: u256
) -> (IERC20Dispatcher, INamingDispatcher, IReferralDispatcher) {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: 100000);
    // pricing
    let pricing = utils::deploy(Pricing::TEST_CLASS_HASH, array![erc20.contract_address.into()]);
    // identity
    let identity = utils::deploy(Identity::TEST_CLASS_HASH, ArrayTrait::<felt252>::new());
    // naming
    let naming = INamingDispatcher {
        contract_address: utils::deploy(
            Naming::TEST_CLASS_HASH, array![identity.into(), pricing.into(), 0, 0]
        )
    };

    // It should initialize the referral contract

    let referral = deploy_referral(
        OWNER(), naming.contract_address, erc20.contract_address, min_claim_amount, share
    );

    (erc20, naming, referral)
}

fn deploy_erc20(recipient: ContractAddress, initial_supply: u256) -> IERC20Dispatcher {
    let address = utils::deploy(
        ERC20::TEST_CLASS_HASH,
        array![initial_supply.low.into(), initial_supply.high.into(), recipient.into()]
    );
    IERC20Dispatcher { contract_address: address }
}

fn deploy_naming() -> INamingDispatcher {
    let address = utils::deploy(Naming::TEST_CLASS_HASH, ArrayTrait::<felt252>::new());
    INamingDispatcher { contract_address: address }
}

fn deploy_referral(
    admin: ContractAddress,
    naming_addr: ContractAddress,
    eth_addr: ContractAddress,
    min_claim_amount: u256,
    share: u256
) -> IReferralDispatcher {
    let address = utils::deploy(
        Referral::TEST_CLASS_HASH,
        array![
            admin.into(),
            naming_addr.into(),
            eth_addr.into(),
            min_claim_amount.low.into(),
            min_claim_amount.high.into(),
            share.low.into(),
            share.high.into()
        ]
    );
    IReferralDispatcher { contract_address: address }
}


fn V2_CLASS_HASH() -> starknet::class_hash::ClassHash {
    Referral_V2::TEST_CLASS_HASH.try_into().unwrap()
}


#[test]
#[available_gas(20000000)]
fn test_deploy_referral_contract() {
    let (_, _, referral) = setup(1, 10);
    assert(referral.owner() == OWNER(), 'Owner is not set correctly');
}

#[test]
#[available_gas(20000000)]
fn test_ownership_transfer() {
    let (_, _, referral) = setup(1, 10);

    assert(referral.owner() == OWNER(), 'Owner is not set correctly');

    // It should test transferring ownership of the referral contract
    testing::set_contract_address(OWNER());
    referral.transfer_ownership(OTHER());
    assert(referral.owner() == OTHER(), 'Ownership transfer failed');
}
#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_ownership_transfer_failed() {
    let (_, _, referral) = setup(1, 10);

    assert(referral.owner() == OWNER(), 'Owner is not set correctly');

    // It should test transferring ownership of the referral contract with a non-admin account
    testing::set_contract_address(OTHER());
    referral.transfer_ownership(OTHER());
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Share must be between 0 and 100', 'ENTRYPOINT_FAILED'))]
fn test_set_default_commission_failed_wrong_share_size() {
    let (_, _, referral) = setup(1, 10);

    // It should test setting up default commission higher than 100%
    testing::set_contract_address(OWNER());
    referral.set_default_commission(1000);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Share must be between 0 and 100', 'ENTRYPOINT_FAILED'))]
fn test_override_commission_wrong_share_size() {
    let (_, _, referral) = setup(1, 10);

    // It should test overriding the default commission with a share higher than 100%
    testing::set_contract_address(OWNER());
    referral.override_commission(OTHER(), 1000);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller not naming contract', 'ENTRYPOINT_FAILED'))]
fn test_add_commission_fail_not_naming_contract() {
    let (_, _, referral) = setup(1, 10);

    // It should test buying a domain from another contract
    testing::set_caller_address(USER());
    referral.add_commission(100, USER(), USER());
}

#[test]
#[available_gas(20000000)]
fn test_add_commission() {
    let default_comm = 10;
    let price_domain = 1000;

    let (_, naming, referral) = setup(1, default_comm);

    let balance = referral.get_balance(OTHER());
    assert(balance == u256 { low: 0, high: 0 }, 'Balance is not 0');

    // It should test calling add_commission from the naming contract & add the right commission
    testing::set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());

    let balance = referral.get_balance(OTHER());
    assert(balance == (price_domain * default_comm) / 100, 'Balance is incorrect');
}

#[test]
#[available_gas(20000000)]
fn test_add_custom_commission() {
    let default_comm = 10;
    let price_domain = 1000;
    let custom_comm = 20;

    let (_, naming, referral) = setup(1, default_comm);

    let balance = referral.get_balance(OTHER());
    assert(balance == u256 { low: 0, high: 0 }, 'Balance is not 0');

    // It should define override the default commission for OTHER() user to 20%
    testing::set_contract_address(OWNER());
    referral.override_commission(OTHER(), custom_comm);

    // It should test calling add_commission from the naming contract & add the right commission
    testing::set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());

    let balance = referral.get_balance(OTHER());
    assert(balance == (price_domain * custom_comm) / (100), 'Balance is incorrect');
}

#[test]
#[available_gas(20000000)]
fn test_withdraw() {
    let default_comm = 10;
    let price_domain = 1000;
    let custom_comm = 20;
    let price_domain = 1000;

    let (erc20, naming, referral) = setup(1, default_comm);

    testing::set_contract_address(OWNER());

    // It sends ETH to referral contract and then withdraw this amount from the contract
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), 100000);
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == 100000, 'Contract balance is not 100000');
    referral.withdraw(OWNER(), 100000);
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == 0, 'Contract balance is not 0');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_fail_not_owner() {
    let default_comm = 10;
    let price_domain = 1000;
    let custom_comm = 20;

    let (erc20, naming, referral) = setup(1, default_comm);

    // It sends ETH to referral contract and then another user try withdrawing this amount
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), 100000);
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == 100000, 'Contract balance is not 100000');

    testing::set_contract_address(OTHER());
    referral.withdraw(OTHER(), 100000);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_fail_zero_addr() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);

    // It sends ETH to referral contract and then try withdraw this amount from the addr zero
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), 100000);
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == 100000, 'Contract balance is not 100000');

    testing::set_contract_address(ZERO());
    referral.withdraw(OTHER(), 100000);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_fail_balance_too_low() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);

    testing::set_contract_address(OWNER());
    // It sends ETH to referral contract and then try withrawing a higher amount from the contract balance
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), 100);
    referral.withdraw(OTHER(), 100000);
}

#[test]
#[available_gas(20000000)]
fn test_claim() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);
    testing::set_contract_address(OWNER());
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), 1000);
    testing::set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());
    let balance = referral.get_balance(OTHER());
    assert(balance == (price_domain * default_comm) / 100, 'Error adding commission');

    // It should test claiming the commission
    testing::set_contract_address(OTHER());
    referral.claim();
    let balance = referral.get_balance(OTHER());
    assert(balance == 0, 'Claiming commissions failed');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_claim_fail_contract_balance_too_low() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);
    testing::set_contract_address(OWNER());
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 10, high: 0 });

    testing::set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());

    // It should test claiming the commission with an amount higher than the balance of the referral contract
    testing::set_contract_address(OTHER());
    referral.claim();
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_upgrade_unauthorized() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);

    // It should test upgrading implementation from a non-admin account
    testing::set_contract_address(OTHER());
    referral.upgrade(V2_CLASS_HASH());
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address', 'ENTRYPOINT_FAILED'))]
fn test_upgrade_fail_from_zero() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);

    // It should test upgrading implementation from the zero address
    referral.upgrade(V2_CLASS_HASH());
}

#[test]
#[available_gas(20000000)]
fn test_add_rec_commission() {
    let default_comm = 10;
    let price_domain = 1000;

    let (erc20, naming, referral) = setup(1, default_comm);

    testing::set_contract_address(OWNER());

    // It sends ETH to referral contract and then withdraw this amount from the contract
    let initial_balance = 10000;
    erc20.transfer_from(OWNER(), USER_A(), initial_balance);
    erc20.transfer_from(OWNER(), USER_B(), initial_balance);
    erc20.transfer_from(OWNER(), USER_C(), initial_balance);

    // It should test calling add_commission from the naming contract & add the right commission
    testing::set_contract_address(naming.contract_address);
    assert(referral.get_balance(USER_A()) == 0, 'Init balance is incorrect');

    // B referred by C
    referral.add_commission(price_domain, USER_C(), USER_B());
    let initial_expected = (price_domain * default_comm) / 100;
    assert(referral.get_balance(USER_B()) == 0, 'Balance of B is incorrect');
    assert(referral.get_balance(USER_C()) == initial_expected, 'Balance of C is incorrect');

    // A referred by B
    referral.add_commission(price_domain, USER_B(), USER_A());

    assert(referral.get_balance(USER_A()) == 0, 'Balance of A is incorrect');
    assert(referral.get_balance(USER_B()) == initial_expected, 'Balance of B is incorrect');
    assert(
        referral.get_balance(USER_C()) == initial_expected + initial_expected / 2,
        'Balance of C is incorrect'
    );
}


#[test]
#[available_gas(20000000)]
fn test_add_rec_circular_commission() {
    // The goal of this test is to ensure that if a circular commission is created,
    // people can still buy domains and will receive a reward only once

    let default_comm = 10;
    let price_domain = 1000;

    let (erc20, naming, referral) = setup(1, default_comm);

    testing::set_contract_address(OWNER());

    // It sends ETH to referral contract and then withdraw this amount from the contract
    let initial_balance = 10000;
    erc20.transfer_from(OWNER(), USER_A(), initial_balance);
    erc20.transfer_from(OWNER(), USER_B(), initial_balance);
    erc20.transfer_from(OWNER(), USER_C(), initial_balance);

    testing::set_contract_address(naming.contract_address);

    // B referred by C
    referral.add_commission(price_domain, USER_C(), USER_B());
    // A referred by B
    referral.add_commission(price_domain, USER_B(), USER_A());
    // C referred by A
    referral.add_commission(price_domain, USER_A(), USER_C());

    let initial_expected = (price_domain * default_comm) / 100;
    assert(
        referral.get_balance(USER_C()) == initial_expected
            + initial_expected / 2
            + initial_expected / 4,
        'Balance of C is incorrect'
    );

    assert(
        referral.get_balance(USER_B()) == initial_expected + initial_expected / 2,
        'Balance of B is incorrect'
    );

    assert(referral.get_balance(USER_A()) == initial_expected, 'Balance of B is incorrect');
}
