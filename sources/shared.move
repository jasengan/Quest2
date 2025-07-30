//Shared module for the quest contract to prevent code duplication

module questcontract::shared {
    use questcontract::lock::{Self, Locked, Key};
    use sui::dynamic_object_field as dof;
    use sui::event;

    public struct EscrowedObjectKey has copy, drop, store {}

    public struct Escrow<phantom T: key + store> has key, store {
        id: UID,
        sender: address,
        recipient: address,
        exchange_key: ID,
    }

    const EMismatchedSenderRecipient: u64 = 0;
    const EMismatchedExchangeObject: u64 = 1;

    public fun create<T: key + store>(
        escrowed: T,
        exchange_key: ID,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        let mut escrow = Escrow<T> {
            id: object::new(ctx),
            sender: tx_context::sender(ctx),
            recipient,
            exchange_key,
        };
        event::emit(EscrowCreated {
            escrow_id: object::id(&escrow),
            key_id: exchange_key,
            sender: escrow.sender,
            recipient,
            item_id: object::id(&escrowed),
        });

        dof::add(&mut escrow.id, EscrowedObjectKey {}, escrowed);

        transfer::public_share_object(escrow);
    }

    public fun swap<T: key + store, U: key + store>(
        mut escrow: Escrow<T>,
        key: Key,
        locked: Locked<U>,
        ctx: &TxContext,
    ): T {
        let escrowed = dof::remove<EscrowedObjectKey, T>(&mut escrow.id, EscrowedObjectKey {});

        let Escrow {
            id,
            sender,
            recipient,
            exchange_key,
        } = escrow;

        assert!(recipient == tx_context::sender(ctx), EMismatchedSenderRecipient);
        assert!(exchange_key == object::id(&key), EMismatchedExchangeObject);

        transfer::public_transfer(lock::unlock(locked, key), sender);

        event::emit(EscrowSwapped {
            escrow_id: id.to_inner(),
        });

        id.delete();

        escrowed
    }

    public fun return_to_sender<T: key + store>(mut escrow: Escrow<T>, ctx: &TxContext): T {
        event::emit(EscrowCancelled {
            escrow_id: object::id(&escrow),
        });

        let escrowed = dof::remove<EscrowedObjectKey, T>(&mut escrow.id, EscrowedObjectKey {});

        let Escrow {
            id,
            sender,
            recipient: _,
            exchange_key: _,
        } = escrow;

        assert!(sender == tx_context::sender(ctx), EMismatchedSenderRecipient);
        id.delete();
        escrowed
    }

    public struct EscrowCreated has copy, drop {
        escrow_id: ID,
        key_id: ID,
        sender: address,
        recipient: address,
        item_id: ID,
    }

    public struct EscrowSwapped has copy, drop {
        escrow_id: ID,
    }

    public struct EscrowCancelled has copy, drop {
        escrow_id: ID,
    }

    #[test_only]
    use sui::coin::{Self, Coin};
    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use sui::test_scenario::{Self as ts, Scenario};
    #[test_only]
    const ALICE: address = @0xA;
    #[test_only]
    const BOB: address = @0xB;

    #[test_only]
    fun test_coin(ts: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(42, ts.ctx())
    }

    #[test]
    fun test_swap() {
        let mut ts = ts::begin(@0x0);
        let dummy_key_id = object::id_from_address(@0x1);
        
        // Create escrow
        {
            ts.next_tx(ALICE);
            let c1: Coin<SUI> = coin::mint_for_testing<SUI>(1000, ts.ctx());
            create(c1, dummy_key_id, BOB, ts.ctx());
        };
        
        // Create locked coin
        {
            ts.next_tx(BOB);
            let c2: Coin<SUI> = coin::mint_for_testing<SUI>(500, ts.ctx());
            let (l2, k2) = lock::lock(c2, ts.ctx());
            transfer::public_transfer(l2, BOB);
            transfer::public_transfer(k2, BOB);
        };
        
        // Perform swap
        {
            ts.next_tx(BOB);
            let escrow: Escrow<Coin<SUI>> = ts.take_shared();
            let k2: Key = ts.take_from_sender();
            let l2: Locked<Coin<SUI>> = ts.take_from_sender();
            let c = swap(escrow, k2, l2, ts.ctx());
            transfer::public_transfer(c, BOB);
        };

        ts::end(ts);
    }
}