module questcontract::questcontract_tests {
    use std::string::{Self, String};
    use std::vector;
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::object;
    use questcontract::questcontract::{
        Self, Platform, Bouty, UserProfile, init_for_testing, register_user, create_bouty,
        apply_for_bouty, submit_bouty_solution, approve_submission,
        reimburse_winner, cancel_bouty, get_bouty, get_user_profile
    };
    use questcontract::lock::{Self, Locked, Key};
    use questcontract::shared::{Self, Escrow};

    // Constants
    const ADMIN: address = @0x1;
    const CREATOR: address = @0x2;
    const CONTRIBUTOR: address = @0x3;
    const CONTRIBUTOR2: address = @0x4;
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_BOUTY_NOT_FOUND: u64 = 2;
    const E_INSUFFICIENT_FUNDS: u64 = 3;
    const E_INVALID_STATUS: u64 = 5;
    const E_NOT_BOUTY_CREATOR: u64 = 6;
    const E_SUBMISSION_NOT_FOUND: u64 = 7;
    const E_ALREADY_APPLIED: u64 = 8;
    const E_BOUTY_EXPIRED: u64 = 9;
    const E_INVALID_RATING: u64 = 10;
    const E_INSUFFICIENT_REPUTATION: u64 = 12;
    const E_MAX_PARTICIPANTS_REACHED: u64 = 13;
    const E_NOT_WINNER: u64 = 14;
    const E_INVALID_ESCROW: u64 = 15;
    const STATUS_OPEN: u8 = 0;
    const STATUS_IN_PROGRESS: u8 = 1;
    const STATUS_COMPLETED: u8 = 2;
    const STATUS_CANCELLED: u8 = 3;
    const DIFFICULTY_BEGINNER: u8 = 1;
    const DIFFICULTY_INTERMEDIATE: u8 = 2;
    const DIFFICULTY_ADVANCED: u8 = 3;
    const CATEGORY_DEVELOPMENT: u8 = 1;
    const CATEGORY_DESIGN: u8 = 2;
    const CATEGORY_MARKETING: u8 = 3;

    // Helper function to create a test coin
    fun create_test_coin(amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ctx)
    }

    // Helper function to create a clock
    fun create_test_clock(ctx: &mut TxContext): Clock {
        clock::create_for_testing(ctx)
    }

    // Helper function to advance clock
    fun advance_clock(clock: &mut Clock, ms: u64) {
        clock::increment_for_testing(clock, ms);
    }

    // Helper function to setup platform and register users
    fun setup_platform_and_users(scenario: &mut Scenario) {
        // Initialize platform
        ts::next_tx(scenario, ADMIN);
        {
            let ctx = ts::ctx(scenario);
            init_for_testing(ctx);
        };
    }

    // Helper function to register a user
    fun register_test_user(
        platform: &mut Platform,
        user: address,
        name: vector<u8>,
        clock: &Clock,
        scenario: &mut Scenario
    ) {
        ts::next_tx(scenario, user);
        {
            let ctx = ts::ctx(scenario);
            register_user(
                platform,
                string::utf8(name),
                vector::empty(),
                string::utf8(b"blob_id"),
                vector::empty(),
                vector::empty(),
                clock,
                ctx,
            );
        };
    }

    // Test lock module: Lock and unlock a coin
    #[test]
    fun test_lock_unlock() {
        let mut scenario = ts::begin(ADMIN);
        let ctx = ts::ctx(&mut scenario);

        // Create a coin
        let coin = create_test_coin(1000, ctx);

        // Lock the coin
        let (locked, key) = lock::lock(coin, ctx);

        // Unlock the coin
        let coin = lock::unlock(locked, key);

        // Verify coin value
        assert!(coin::value(&coin) == 1000, 0);

        // Clean up
        coin::burn_for_testing(coin);
        ts::end(scenario);
    }

    // Test lock module: Fail on key mismatch
    #[test]
    #[expected_failure(abort_code = lock::ELockKeyMismatch)]
    fun test_lock_key_mismatch() {
        let mut scenario = ts::begin(ADMIN);
        let ctx = ts::ctx(&mut scenario);

        // Create two coins
        let coin1 = create_test_coin(1000, ctx);
        let coin2 = create_test_coin(1000, ctx);

        // Lock both coins
        let (locked1, _key1) = lock::lock(coin1, ctx);
        let (_locked2, key2) = lock::lock(coin2, ctx);

        // Try to unlock with wrong key - this should fail
        let _coin = lock::unlock(locked1, key2);
        abort 1337
    }

    // Test shared module: Successful escrow swap
    #[test]
    fun test_escrow_swap() {
        let mut scenario = ts::begin(ADMIN);

        // Creator creates a coin
        ts::next_tx(&mut scenario, CREATOR);
        let creator_coin = {
            let ctx = ts::ctx(&mut scenario);
            create_test_coin(1000, ctx)
        };

        // Contributor creates a coin and locks it
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        let (locked, key, key_id) = {
            let ctx = ts::ctx(&mut scenario);
            let contributor_coin = create_test_coin(500, ctx);
            let (locked, key) = lock::lock(contributor_coin, ctx);
            let key_id = object::id(&key);
            (locked, key, key_id)
        };
        transfer::public_transfer(locked, CONTRIBUTOR);
        transfer::public_transfer(key, CONTRIBUTOR);

        // Creator creates escrow
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            shared::create(creator_coin, key_id, CONTRIBUTOR, ctx);
        };
        let escrow: Escrow<Coin<SUI>> = ts::take_shared(&scenario);

        // Contributor performs swap
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        let creator_coin = {
            let locked: Locked<Coin<SUI>> = ts::take_from_sender(&mut scenario);
            let key: Key = ts::take_from_sender(&mut scenario);
            let ctx = ts::ctx(&mut scenario);
            shared::swap(escrow, key, locked, ctx)
        };
        transfer::public_transfer(creator_coin, CONTRIBUTOR);

        // Verify contributor received creator's coin
        let coin: Coin<SUI> = ts::take_from_address(&scenario, CONTRIBUTOR);
        assert!(coin::value(&coin) == 1000, 0);
        coin::burn_for_testing(coin);

        // Verify creator received contributor's coin
        ts::next_tx(&mut scenario, CREATOR);
        let coin: Coin<SUI> = ts::take_from_address(&scenario, CREATOR);
        assert!(coin::value(&coin) == 500, 0);
        coin::burn_for_testing(coin);

        ts::end(scenario);
    }

    // Test shared module: Return to sender
    #[test]
    fun test_escrow_return_to_sender() {
        let mut scenario = ts::begin(ADMIN);

        // Creator creates a coin
        ts::next_tx(&mut scenario, CREATOR);
        let (creator_coin, ctx) = {
            let ctx = ts::ctx(&mut scenario);
            let coin = create_test_coin(1000, ctx);
            (coin, ctx)
        };

        // Create escrow
        let dummy_key_id = object::id_from_address(@0x0);
        shared::create(creator_coin, dummy_key_id, CONTRIBUTOR, ctx);
        let escrow: Escrow<Coin<SUI>> = ts::take_shared(&scenario);

        // Creator cancels escrow
        ts::next_tx(&mut scenario, CREATOR);
        let refund_coin = {
            let ctx = ts::ctx(&mut scenario);
            shared::return_to_sender(escrow, ctx)
        };
        assert!(coin::value(&refund_coin) == 1000, 0);
        coin::burn_for_testing(refund_coin);

        ts::end(scenario);
    }

    // Test questcontract: Complete bounty workflow
    #[test]
    fun test_complete_bounty_workflow() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);

        // Create bounty
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Build a smart contract"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000, // 24 hours from now
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Verify bounty was created
        let bounty = get_bouty(&platform, 1);
        assert!(questcontract::get_bouty_id(bounty) == 1, 0);
        assert!(questcontract::get_bouty_status(bounty) == STATUS_OPEN, 1);

        // Apply for bounty
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"I can do this"), &clock, ctx);
        };

        // Submit solution
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
                         submit_bouty_solution(
                 &mut platform, 
                 1, 
                 string::utf8(b"Here is my solution"), 
                 string::utf8(b"Solution description"),
                 string::utf8(b"solution_blob_id"),
                 vector::empty(),
                 &clock,
                 ctx
             );
        };

        // Approve submission
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            approve_submission(&mut platform, 1, 1, 5, string::utf8(b"Good work"), false, &clock, ctx);
        };

        // Verify bounty status changed to completed
        let bounty = get_bouty(&platform, 1);
        assert!(questcontract::get_bouty_status(bounty) == STATUS_COMPLETED, 2);

        // Reimburse winner
        let escrow_id = questcontract::get_bouty_escrow_id(bounty);
        let escrow: Escrow<Coin<SUI>> = ts::take_shared_by_id(&scenario, escrow_id);
        
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            reimburse_winner(&mut platform, 1, escrow, platform_key, platform_locked, ctx);
        };

        // Verify winner received payment
        let reward_coin: Coin<SUI> = ts::take_from_address(&scenario, CONTRIBUTOR);
        assert!(coin::value(&reward_coin) == 1000, 3);
        coin::burn_for_testing(reward_coin);

        // Clean up
        clock::destroy_for_testing(clock);
        ts::return_shared(platform);
        ts::end(scenario);
    }

    // Test questcontract: Apply for bounty twice (should fail)
    #[test]
    #[expected_failure(abort_code = E_ALREADY_APPLIED)]
    fun test_double_application() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);

        // Create bounty
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Apply for bounty first time
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"First application"), &clock, ctx);
        };

        // Apply for bounty second time (should fail)
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Second application"), &clock, ctx);
        };
        
        abort 1337
    }

    // Test questcontract: Maximum participants reached
    #[test]
    #[expected_failure(abort_code = E_MAX_PARTICIPANTS_REACHED)]
    fun test_max_participants_reached() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor1", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR2, b"Contributor2", &clock, &mut scenario);

        // Create bounty with max 1 participant
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                1, // Max participants = 1
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // First contributor applies
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"First application"), &clock, ctx);
        };

        // Second contributor tries to apply (should fail)
        ts::next_tx(&mut scenario, CONTRIBUTOR2);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Second application"), &clock, ctx);
        };
        
        abort 1337
    }

    // Test questcontract: Submit solution without applying first
    #[test]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED)]
    fun test_submit_solution_without_applying() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);

        // Create bounty
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Try to submit solution without applying first (should fail)
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            submit_bouty_solution(
                &mut platform, 
                1, 
                string::utf8(b"My solution"), 
                string::utf8(b"Solution description"),
                string::utf8(b"solution_blob_id"),
                vector::empty(),
                &clock,
                ctx
            );
        };
        
        abort 1337
    }

    // Test questcontract: Approve non-existent submission
    #[test]
    #[expected_failure(abort_code = E_SUBMISSION_NOT_FOUND)]
    fun test_approve_nonexistent_submission() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);

        // Create bounty
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Apply for bounty
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Application"), &clock, ctx);
        };

        // Try to approve submission that doesn't exist (should fail)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            approve_submission(&mut platform, 1, 0, 5, string::utf8(b"Good work"), false, &clock, ctx);
        };
        
        abort 1337
    }

    // Test questcontract: Invalid rating (out of bounds)
    #[test]
    #[expected_failure(abort_code = E_INVALID_RATING)]
    fun test_invalid_rating() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);

        // Create bounty
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Apply and submit solution
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Application"), &clock, ctx);
            submit_bouty_solution(
                &mut platform, 
                1, 
                string::utf8(b"Solution"), 
                string::utf8(b"Solution description"),
                string::utf8(b"solution_blob_id"),
                vector::empty(),
                &clock,
                ctx
            );
        };

        // Try to approve with invalid rating (should fail)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            approve_submission(&mut platform, 1, 0, 11, string::utf8(b"Good work"), false, &clock, ctx); // Rating > 10
        };
        
        abort 1337
    }

    // Test questcontract: Non-creator tries to approve submission
    #[test]
    #[expected_failure(abort_code = E_NOT_BOUTY_CREATOR)]
    fun test_non_creator_approve() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR2, b"Contributor2", &clock, &mut scenario);

        // Create bounty
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Apply and submit solution
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Application"), &clock, ctx);
            submit_bouty_solution(
                &mut platform, 
                1, 
                string::utf8(b"Solution"), 
                string::utf8(b"Solution description"),
                string::utf8(b"solution_blob_id"),
                vector::empty(),
                &clock,
                ctx
            );
        };

        // Non-creator tries to approve (should fail)
        ts::next_tx(&mut scenario, CONTRIBUTOR2);
        {
            let ctx = ts::ctx(&mut scenario);
            approve_submission(&mut platform, 1, 0, 5, string::utf8(b"Good work"), false, &clock, ctx);
        };
        
        abort 1337
    }

    // Test questcontract: Cancel bounty
    #[test]
    fun test_cancel_bounty() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register creator
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);

        // Create bounty
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Get escrow and cancel bounty
        let bounty = get_bouty(&platform, 1);
        let escrow_id = questcontract::get_bouty_escrow_id(bounty);
        let escrow: Escrow<Coin<SUI>> = ts::take_shared_by_id(&scenario, escrow_id);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            cancel_bouty(&mut platform, 1, string::utf8(b"Cancelled"), escrow, ctx);
        };

        // Verify bounty status
        let bounty = get_bouty(&platform, 1);
        assert!(questcontract::get_bouty_status(bounty) == STATUS_CANCELLED, 0);

        // Verify creator received refund
        let coin: Coin<SUI> = ts::take_from_address(&scenario, CREATOR);
        assert!(coin::value(&coin) == 1200, 1); // 1000 + 200
        coin::burn_for_testing(coin);

        // Clean up
        clock::destroy_for_testing(clock);
        ts::return_shared(platform);
        ts::end(scenario);
    }

    // Test questcontract: Non-existent bounty
    #[test]
    #[expected_failure(abort_code = E_BOUTY_NOT_FOUND)]
    fun test_nonexistent_bounty() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register contributor
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);

        // Try to apply for non-existent bounty (should fail)
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 999, string::utf8(b"Application"), &clock, ctx);
        };
        
        abort 1337
    }

    // Test questcontract: Reimburse unauthorized user
    #[test]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED)]
    fun test_unauthorized_reimbursement() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);

        // Create and complete bounty workflow
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Apply, submit, and approve
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Application"), &clock, ctx);
            submit_bouty_solution(
                &mut platform, 
                1, 
                string::utf8(b"Solution"), 
                string::utf8(b"Solution description"),
                string::utf8(b"solution_blob_id"),
                vector::empty(),
                &clock,
                ctx
            );
        };

        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            approve_submission(&mut platform, 1, 0, 5, string::utf8(b"Good work"), false, &clock, ctx);
        };

        // Get escrow
        let bounty = get_bouty(&platform, 1);
        let escrow_id = questcontract::get_bouty_escrow_id(bounty);
        let escrow: Escrow<Coin<SUI>> = ts::take_shared_by_id(&scenario, escrow_id);

        // Unauthorized user tries to reimburse (should fail)
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            reimburse_winner(&mut platform, 1, escrow, platform_key, platform_locked, ctx);
        };
        
        abort 1337
    }

    // Test questcontract: Invalid escrow for reimbursement
    #[test]
    #[expected_failure(abort_code = E_INVALID_ESCROW)]
    fun test_invalid_escrow_reimbursement() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);

        // Create and complete bounty workflow
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Apply, submit, and approve
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Application"), &clock, ctx);
            submit_bouty_solution(
                &mut platform, 
                1, 
                string::utf8(b"Solution"), 
                string::utf8(b"Solution description"),
                string::utf8(b"solution_blob_id"),
                vector::empty(),
                &clock,
                ctx
            );
        };

        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            approve_submission(&mut platform, 1, 0, 5, string::utf8(b"Good work"), false, &clock, ctx);
        };

        // Create a different escrow (wrong one)
        ts::next_tx(&mut scenario, CREATOR);
        let wrong_escrow = {
            let ctx = ts::ctx(&mut scenario);
            let dummy_coin = create_test_coin(500, ctx);
            let dummy_key_id = object::id_from_address(@0x0);
            shared::create(dummy_coin, dummy_key_id, CONTRIBUTOR, ctx);
            ts::take_shared(&scenario)
        };

        // Try to reimburse with wrong escrow (should fail)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            reimburse_winner(&mut platform, 1, wrong_escrow, platform_key, platform_locked, ctx);
        };
        
        abort 1337
    }

    // Test questcontract: Insufficient funds for bounty creation
    #[test]
    #[expected_failure(abort_code = E_INSUFFICIENT_FUNDS)]
    fun test_insufficient_funds_bounty_creation() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register creator
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);

        // Try to create bounty with zero funds (should fail)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(0, ctx); // Zero funds
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };
        
        abort 1337
    }

    // Test questcontract: Expired bounty application
    #[test]
    #[expected_failure(abort_code = E_BOUTY_EXPIRED)]
    fun test_expired_bounty_application() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);

        // Create bounty with short deadline
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 1000, // Very short deadline
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Advance clock past deadline
        advance_clock(&mut clock, 2000);

        // Try to apply after deadline (should fail)
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Late application"), &clock, ctx);
        };
        
        abort 1337
    }

    // Test questcontract: User profile verification
    #[test]
    fun test_user_profile_creation() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register user with detailed profile
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let mut skills = vector::empty<String>();
            vector::push_back(&mut skills, string::utf8(b"Development"));
            vector::push_back(&mut skills, string::utf8(b"Design"));
            
            let mut languages = vector::empty<String>();
            vector::push_back(&mut languages, string::utf8(b"English"));
            vector::push_back(&mut languages, string::utf8(b"Spanish"));
            
            register_user(
                &mut platform,
                string::utf8(b"Test Creator"),
                vector::empty(),
                string::utf8(b"profile_blob_id"),
                skills,
                languages,
                &clock,
                ctx,
            );
        };

        // Verify user profile was created correctly
        let profile = get_user_profile(&platform, CREATOR);
        assert!(questcontract::get_user_reputation(profile) == 50, 0); // Default reputation
        assert!(questcontract::get_user_completed_bounties(profile) == 0, 1);

        // Clean up
        clock::destroy_for_testing(clock);
        ts::return_shared(platform);
        ts::end(scenario);
    }

    // Test questcontract: Bounty status transitions
    #[test]
    fun test_bounty_status_transitions() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor", &clock, &mut scenario);

        // Create bounty (should be OPEN)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Verify initial status is OPEN
        let bounty = get_bouty(&platform, 1);
        assert!(questcontract::get_bouty_status(bounty) == STATUS_OPEN, 0);

        // Apply for bounty (should remain OPEN until someone submits)
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Application"), &clock, ctx);
        };

        let bounty = get_bouty(&platform, 1);
        assert!(questcontract::get_bouty_status(bounty) == STATUS_OPEN, 1);

        // Submit solution (should change to IN_PROGRESS)
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            submit_bouty_solution(
                &mut platform, 
                1, 
                string::utf8(b"Solution"), 
                string::utf8(b"Solution description"),
                string::utf8(b"solution_blob_id"),
                vector::empty(),
                &clock,
                ctx
            );
        };

        let bounty = get_bouty(&platform, 1);
        assert!(questcontract::get_bouty_status(bounty) == STATUS_IN_PROGRESS, 2);

        // Approve submission (should change to COMPLETED)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            approve_submission(&mut platform, 1, 0, 5, string::utf8(b"Good work"), false, &clock, ctx);
        };

        let bounty = get_bouty(&platform, 1);
        assert!(questcontract::get_bouty_status(bounty) == STATUS_COMPLETED, 3);

        // Clean up
        clock::destroy_for_testing(clock);
        ts::return_shared(platform);
        ts::end(scenario);
    }

    // Test questcontract: Edge case - Apply to already completed bounty
    #[test]
    #[expected_failure(abort_code = E_INVALID_STATUS)]
    fun test_apply_to_completed_bounty() {
        let mut scenario = ts::begin(ADMIN);
        
        setup_platform_and_users(&mut scenario);
        
        let mut platform: Platform = ts::take_shared(&scenario);
        let mut clock = {
            let ctx = ts::ctx(&mut scenario);
            create_test_clock(ctx)
        };

        // Register users
        register_test_user(&mut platform, CREATOR, b"Creator", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR, b"Contributor1", &clock, &mut scenario);
        register_test_user(&mut platform, CONTRIBUTOR2, b"Contributor2", &clock, &mut scenario);

        // Create and complete bounty workflow
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward = create_test_coin(1000, ctx);
            let platform_coin = create_test_coin(100, ctx);
            let (platform_locked, platform_key) = lock::lock(platform_coin, ctx);
            
            create_bouty(
                &mut platform,
                string::utf8(b"Test Bounty"),
                string::utf8(b"Description"),
                string::utf8(b"metadata"),
                reward,
                200,
                clock::timestamp_ms(&clock) + 86400000,
                DIFFICULTY_BEGINNER,
                CATEGORY_DEVELOPMENT,
                vector::empty(),
                50,
                5,
                10,
                vector::empty(),
                false,
                platform_key,
                platform_locked,
                &clock,
                ctx,
            );
        };

        // Complete the bounty
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Application"), &clock, ctx);
            submit_bouty_solution(
                &mut platform, 
                1, 
                string::utf8(b"Solution"), 
                string::utf8(b"Solution description"),
                string::utf8(b"solution_blob_id"),
                vector::empty(),
                &clock,
                ctx
            );
        };

        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            approve_submission(&mut platform, 1, 0, 5, string::utf8(b"Good work"), false, &clock, ctx);
        };

        // Try to apply to completed bounty (should fail)
        ts::next_tx(&mut scenario, CONTRIBUTOR2);
        {
            let ctx = ts::ctx(&mut scenario);
            apply_for_bouty(&mut platform, 1, string::utf8(b"Late application"), &clock, ctx);
        };
        
        abort 1337
    }
}