
/// Module: questcontract
// module questcontract::questcontract;

// For Move coding conventions, see
// https://docs.sui.io/concepts/sui-move-concepts/conventions
module questcontract::questcontract {
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use std::vector;
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::hash;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_set::{Self, VecSet};

// Error codes
const E_NOT_AUTHORIZED: u64 = 1;
const E_BOUTY_NOT_FOUND: u64 = 2;
const E_INSUFFICIENT_FUNDS: u64 = 3;
const E_BOUTY_ALREADY_CLAIMED: u64 = 4;
const E_INVALID_STATUS: u64 = 5;
const E_NOT_BOUTY_CREATOR: u64 = 6;
const E_SUBMISSION_NOT_FOUND: u64 = 7;
const E_ALREADY_APPLIED: u64 = 8;
const E_BOUTY_EXPIRED: u64 = 9;
const E_INVALID_RATING: u64 = 10;
const E_ALREADY_RATED: u64 = 11;
const E_INSUFFICIENT_REPUTATION: u64 = 12;
const E_MAX_PARTICIPANTS_REACHED: u64 = 13;

// Bouty status
const STATUS_OPEN: u8 = 0;
const STATUS_IN_PROGRESS: u8 = 1;
const STATUS_COMPLETED: u8 = 2;
const STATUS_CANCELLED: u8 = 3;
const STATUS_EXPIRED: u8 = 4;

// Bouty difficulty levels
const DIFFICULTY_BEGINNER: u8 = 1;
const DIFFICULTY_INTERMEDIATE: u8 = 2;
const DIFFICULTY_ADVANCED: u8 = 3;
const DIFFICULTY_EXPERT: u8 = 4;

// Bouty categories
const CATEGORY_DEVELOPMENT: u8 = 1;
const CATEGORY_DESIGN: u8 = 2;
const CATEGORY_MARKETING: u8 = 3;
const CATEGORY_RESEARCH: u8 = 4;
const CATEGORY_TESTING: u8 = 5;
const CATEGORY_DOCUMENTATION: u8 = 6;

// Platform struct: Main contract state
public struct Platform has key {
    id: UID,
    admin: address,
    bouties: Table<u64, Bouty>,
    user_profiles: Table<address, UserProfile>,
    bouty_categories: Table<u8, String>,
    next_bouty_id: u64,
    platform_fee_bps: u64, // basis points (100 = 1%)
    treasury: Balance<SUI>,
    min_reputation_for_bouty_creation: u64,
    max_active_bouties_per_user: u64,
    version: u64,
}

 // Enhanced user profile with reputation system
 public struct UserProfile has store {
     wallet_address: address,
     username: String,
     email_hash: vector<u8>, // Hashed email for privacy
     walrus_profile_blob_id: String,
    reputation_score: u64,
    total_earned: u64,
    bouties_completed: u64,
    bouties_created: u64,
    success_rate: u64, // Percentage (0-100)
    average_rating: u64, // Out of 5 stars (0-500, where 500 = 5.0 stars)
    skills: VecSet<String>,
    languages: VecSet<String>,
    badges: vector<Badge>,
    created_at: u64,
    last_active: u64,
    is_verified: bool,
    is_premium: bool,
}

// Enhanced bouty structure
public struct Bouty has store {
    id: u64,
    creator: address,
    title: String,
    description: String,
    walrus_metadata_blob_id: String,
    reward_base: u64,
    bonus_reward: u64, // Additional reward for exceptional work
    status: u8,
    difficulty: u8,
    category: u8,
    required_skills: vector<String>,
    required_reputation: u64,
    max_participants: u64,
    participants: VecSet<address>,
    assignee: Option<address>,
    created_at: u64,
    deadline: u64,
    estimated_hours: u64,
    submissions: vector<Submission>,
    reviews: vector<Review>,
    tags: vector<String>,
    is_featured: bool,
    is_urgent: bool,
}

// Enhanced submission with milestone tracking
public struct Submission has store {
    id: u64,
    contributor: address,
    bouty_id: u64,
    submission_url: String,
    description: String,
    walrus_submission_blob_id: String,
    submitted_at: u64,
    status: u8, // 0: pending, 1: approved, 2: rejected, 3: needs_revision
    feedback: String,
    milestones: vector<Milestone>,
    final_rating: Option<u64>,
}

// Milestone tracking for complex bouties
public struct Milestone has store {
    id: u64,
    title: String,
    description: String,
    is_completed: bool,
    completed_at: Option<u64>,
    proof_url: String,
}

// Review system for completed bouties
public struct Review has store {
    reviewer: address,
    reviewee: address,
    bouty_id: u64,
    rating: u64, // 1-5 stars
    comment: String,
    created_at: u64,
    is_creator_review: bool, // true if creator reviewing participant, false otherwise
}

// Badge system for achievements
public struct Badge has store {
    badge_type: String,
    title: String,
    description: String,
    earned_at: u64,
    bouty_id: Option<u64>, // Bouty that earned this badge
}

// Dispute system
public struct Dispute has store {
    id: u64,
    bouty_id: u64,
    complainant: address,
    respondent: address,
    reason: String,
    evidence_blob_id: String,
    status: u8, // 0: open, 1: resolved, 2: dismissed
    resolution: String,
    created_at: u64,
    resolved_at: Option<u64>,
}

// Events
public struct PlatformCreated has copy, drop {
    platform_id: address,
    admin: address,
    version: u64,
}

public struct UserRegistered has copy, drop {
    user_address: address,
    username: String,
    timestamp: u64,
}

public struct BoutyCreated has copy, drop {
    bouty_id: u64,
    creator: address,
    title: String,
    reward_amount: u64,
    difficulty: u8,
    category: u8,
    deadline: u64,
}

public struct BoutyAssigned has copy, drop {
    bouty_id: u64,
    assignee: address,
    timestamp: u64,
}

public struct SubmissionCreated has copy, drop {
    bouty_id: u64,
    submission_id: u64,
    contributor: address,
    timestamp: u64,
}

public struct BoutyCompleted has copy, drop {
    bouty_id: u64,
    winner: address,
    reward_amount: u64,
    bonus_amount: u64,
    platform_fee: u64,
    final_rating: u64,
}

public struct ReviewSubmitted has copy, drop {
    bouty_id: u64,
    reviewer: address,
    reviewee: address,
    rating: u64,
    timestamp: u64,
}

public struct BadgeEarned has copy, drop {
    user: address,
    badge_type: String,
    bouty_id: Option<u64>,
    timestamp: u64,
}

// Initialize platform with enhanced configuration
fun init(ctx: &mut TxContext) {
    let mut bouty_categories = table::new(ctx);
    table::add(&mut bouty_categories, CATEGORY_DEVELOPMENT, string::utf8(b"Development"));
    table::add(&mut bouty_categories, CATEGORY_DESIGN, string::utf8(b"Design"));
    table::add(&mut bouty_categories, CATEGORY_MARKETING, string::utf8(b"Marketing"));
    table::add(&mut bouty_categories, CATEGORY_RESEARCH, string::utf8(b"Research"));
    table::add(&mut bouty_categories, CATEGORY_TESTING, string::utf8(b"Testing"));
    table::add(&mut bouty_categories, CATEGORY_DOCUMENTATION, string::utf8(b"Documentation"));

    let platform = Platform {
        id: object::new(ctx),
        admin: tx_context::sender(ctx),
        bouties: table::new(ctx),
        user_profiles: table::new(ctx),
        bouty_categories,
        next_bouty_id: 1,
        platform_fee_bps: 250, // 2.5%
        treasury: balance::zero(),
        min_reputation_for_bouty_creation: 50,
        max_active_bouties_per_user: 5,
        version: 1,
    };

    event::emit(PlatformCreated {
        platform_id: object::uid_to_address(&platform.id),
        admin: tx_context::sender(ctx),
        version: 1,
    });

    transfer::share_object(platform);
}

// Enhanced user registration
public entry fun register_user(
    platform: &mut Platform,
    username: String,
    email_hash: vector<u8>,


    walrus_profile_blob_id: String,
    skills: vector<String>,
    languages: vector<String>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let user_address = tx_context::sender(ctx);
    assert!(!table::contains(&platform.user_profiles, user_address), E_ALREADY_APPLIED);
    let mut skills_set = vec_set::empty();
    let mut languages_set = vec_set::empty();
    
    let mut i = 0;
    while (i < vector::length(&skills)) {
        vec_set::insert(&mut skills_set, *vector::borrow(&skills, i));
        i = i + 1;
    };
    
    i = 0;
    while (i < vector::length(&languages)) {
        vec_set::insert(&mut languages_set, *vector::borrow(&languages, i));
        i = i + 1;
    };

    let profile = UserProfile {
        wallet_address: user_address,
        username,
        email_hash,
        walrus_profile_blob_id,
        reputation_score: 100, // Starting reputation
        total_earned: 0,
        bouties_completed: 0,
        bouties_created: 0,
        success_rate: 100, // Start with perfect success rate
        average_rating: 0,
        skills: skills_set,
        languages: languages_set,
        badges: vector::empty(),
        created_at: clock::timestamp_ms(clock),
        last_active: clock::timestamp_ms(clock),
        is_verified: false,
        is_premium: false,
    };

    table::add(&mut platform.user_profiles, user_address, profile);

    event::emit(UserRegistered {
        user_address,
        username,
        timestamp: clock::timestamp_ms(clock),
    });
}

// Enhanced bouty creation with validation
public entry fun create_bouty(
    platform: &mut Platform,
    title: String,
    description: String,
    walrus_metadata_blob_id: String,
    reward: Coin<SUI>,
    bonus_reward_amount: u64,
    deadline: u64,
    difficulty: u8,
    category: u8,
    required_skills: vector<String>,
    required_reputation: u64,
    max_participants: u64,
    estimated_hours: u64,
    tags: vector<String>,
    is_urgent: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let creator = tx_context::sender(ctx);
    assert!(table::contains(&platform.user_profiles, creator), E_NOT_AUTHORIZED);
    
    let creator_profile = table::borrow(&platform.user_profiles, creator);
    assert!(creator_profile.reputation_score >= platform.min_reputation_for_bouty_creation, E_INSUFFICIENT_REPUTATION);
    
    let reward_amount = coin::value(&reward);
    assert!(reward_amount > 0, E_INSUFFICIENT_FUNDS);
    assert!(deadline > clock::timestamp_ms(clock), E_BOUTY_EXPIRED);
    assert!(difficulty >= DIFFICULTY_BEGINNER && difficulty <= DIFFICULTY_EXPERT, E_INVALID_STATUS);
    assert!(table::contains(&platform.bouty_categories, category), E_INVALID_STATUS);

    let bouty_id = platform.next_bouty_id;
    platform.next_bouty_id = bouty_id + 1;

    let bouty = Bouty {
        id: bouty_id,
        creator,
        title,
        description,
        walrus_metadata_blob_id,
        reward_base: reward_amount,
        bonus_reward: bonus_reward_amount,
        status: STATUS_OPEN,
        difficulty,
        category,
        required_skills,
        required_reputation,
        max_participants,
        participants: vec_set::empty(),
        assignee: option::none(),
        created_at: clock::timestamp_ms(clock),
        deadline,
        estimated_hours,
        submissions: vector::empty(),
        reviews: vector::empty(),
        tags,
        is_featured: false,
        is_urgent,
    };

    table::add(&mut platform.bouties, bouty_id, bouty);
    balance::join(&mut platform.treasury, coin::into_balance(reward));

    // Update creator's bouty count
    let creator_profile_mut = table::borrow_mut(&mut platform.user_profiles, creator);
    creator_profile_mut.bouties_created = creator_profile_mut.bouties_created + 1;

    event::emit(BoutyCreated {
        bouty_id,
        creator,
        title,
        reward_amount,
        difficulty,
        category,
        deadline,
    });
}

// Enhanced bouty application with validation
public entry fun apply_for_bouty(
    platform: &mut Platform,
    bouty_id: u64,
    proposal_message: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let applicant = tx_context::sender(ctx);
    assert!(table::contains(&platform.user_profiles, applicant), E_NOT_AUTHORIZED);
    assert!(table::contains(&platform.bouties, bouty_id), E_BOUTY_NOT_FOUND);

    let bouty = table::borrow_mut(&mut platform.bouties, bouty_id);
    assert!(bouty.status == STATUS_OPEN, E_INVALID_STATUS);
    assert!(bouty.deadline > clock::timestamp_ms(clock), E_BOUTY_EXPIRED);
    assert!(!vec_set::contains(&bouty.participants, &applicant), E_ALREADY_APPLIED);
    assert!(vec_set::size(&bouty.participants) < bouty.max_participants, E_MAX_PARTICIPANTS_REACHED);

    let applicant_profile = table::borrow_mut(&mut platform.user_profiles, applicant);
    assert!(applicant_profile.reputation_score >= bouty.required_reputation, E_INSUFFICIENT_REPUTATION);

    // Add to participants
    vec_set::insert(&mut bouty.participants, applicant);
    
    // For now, auto-assign first qualified applicant (can be enhanced with selection process)
    if (option::is_none(&bouty.assignee)) {
        bouty.status = STATUS_IN_PROGRESS;
        bouty.assignee = option::some(applicant);
        
        applicant_profile.last_active = clock::timestamp_ms(clock);

        event::emit(BoutyAssigned {
            bouty_id,
            assignee: applicant,
            timestamp: clock::timestamp_ms(clock),
        });
    };
}

// Enhanced submission with milestone tracking
public entry fun submit_bouty_solution(
    platform: &mut Platform,
    bouty_id: u64,
    submission_url: String,
    description: String,
    walrus_submission_blob_id: String,
    milestone_proofs: vector<String>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let contributor = tx_context::sender(ctx);
    assert!(table::contains(&platform.user_profiles, contributor), E_NOT_AUTHORIZED);
    assert!(table::contains(&platform.bouties, bouty_id), E_BOUTY_NOT_FOUND);

    let bouty = table::borrow_mut(&mut platform.bouties, bouty_id);
    assert!(bouty.status == STATUS_IN_PROGRESS, E_INVALID_STATUS);
    assert!(option::contains(&bouty.assignee, &contributor), E_NOT_AUTHORIZED);
    assert!(bouty.deadline > clock::timestamp_ms(clock), E_BOUTY_EXPIRED);

    let submission_id = vector::length(&bouty.submissions);
    let mut milestones = vector::empty<Milestone>();
    
    // Create milestones from proofs
    let mut i = 0;
    while (i < vector::length(&milestone_proofs)) {
        let milestone = Milestone {
            id: i,
            title: string::utf8(b"Milestone"),
            description: string::utf8(b"Milestone completed"),
            is_completed: true,
            completed_at: option::some(clock::timestamp_ms(clock)),
            proof_url: *vector::borrow(&milestone_proofs, i),
        };
        vector::push_back(&mut milestones, milestone);
        i = i + 1;
    };

    let submission = Submission {
        id: submission_id,
        contributor,
        bouty_id,
        submission_url,
        description,
        walrus_submission_blob_id,
        submitted_at: clock::timestamp_ms(clock),
        status: 0, // pending
        feedback: string::utf8(b""),
        milestones,
        final_rating: option::none(),
    };

    vector::push_back(&mut bouty.submissions, submission);

    event::emit(SubmissionCreated {
        bouty_id,
        submission_id,
        contributor,
        timestamp: clock::timestamp_ms(clock),
    });
}

// Enhanced bouty completion with rating system
public entry fun complete_bouty(
    platform: &mut Platform,
    bouty_id: u64,
    submission_id: u64,
    rating: u64,
    feedback: String,
    award_bonus: bool,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    assert!(table::contains(&platform.bouties, bouty_id), E_BOUTY_NOT_FOUND);
    assert!(rating >= 1 && rating <= 5, E_INVALID_RATING);

    let bouty = table::borrow_mut(&mut platform.bouties, bouty_id);
    assert!(bouty.creator == sender, E_NOT_BOUTY_CREATOR);
    assert!(bouty.status == STATUS_IN_PROGRESS, E_INVALID_STATUS);
    assert!(submission_id < vector::length(&bouty.submissions), E_SUBMISSION_NOT_FOUND);

    let submission = vector::borrow_mut(&mut bouty.submissions, submission_id);
    let winner = submission.contributor;
    
    // Calculate rewards
    let base_reward = bouty.reward_base;
    let bonus_amount = if (award_bonus) bouty.bonus_reward else 0;
    let total_reward = base_reward + bonus_amount;
    let platform_fee = (total_reward * platform.platform_fee_bps) / 10000;
    let winner_amount = total_reward - platform_fee;

    // Update bouty and submission
    bouty.status = STATUS_COMPLETED;
    submission.status = 1; // approved
    submission.feedback = feedback;
    submission.final_rating = option::some(rating);

    // Update winner's profile
    let winner_profile = table::borrow_mut(&mut platform.user_profiles, winner);
    winner_profile.total_earned = winner_profile.total_earned + winner_amount;
    winner_profile.bouties_completed = winner_profile.bouties_completed + 1;
    winner_profile.reputation_score = winner_profile.reputation_score + (rating * 2);
    
    // Update average rating
    let total_rating_points = winner_profile.average_rating * (winner_profile.bouties_completed - 1) + (rating * 100);
    winner_profile.average_rating = total_rating_points / winner_profile.bouties_completed;

    // Award badges based on performance
    if (rating == 5) {
        let excellence_badge = Badge {
            badge_type: string::utf8(b"EXCELLENCE"),
            title: string::utf8(b"Excellence Award"),
            description: string::utf8(b"Achieved 5-star rating on bouty completion"),
            earned_at: submission.submitted_at,
            bouty_id: option::some(bouty_id),
        };
        vector::push_back(&mut winner_profile.badges, excellence_badge);
        
        event::emit(BadgeEarned {
            user: winner,
            badge_type: string::utf8(b"EXCELLENCE"),
            bouty_id: option::some(bouty_id),
            timestamp: submission.submitted_at,
        });
    };

    // Transfer rewards
    let reward_balance = balance::split(&mut platform.treasury, winner_amount);
    let reward_coin = coin::from_balance(reward_balance, ctx);
    transfer::public_transfer(reward_coin, winner);

    event::emit(BoutyCompleted {
        bouty_id,
        winner,
        reward_amount: winner_amount,
        bonus_amount,
        platform_fee,
        final_rating: rating,
    });
}

// View functions
public fun get_user_profile(platform: &Platform, user: address): &UserProfile {
    table::borrow(&platform.user_profiles, user)
}

public fun get_bouty(platform: &Platform, bouty_id: u64): &Bouty {
    table::borrow(&platform.bouties, bouty_id)
}

public fun get_platform_stats(platform: &Platform): (u64, u64, u64, u64) {
    (
        platform.next_bouty_id - 1, // total bouties
        table::length(&platform.user_profiles), // total users
        balance::value(&platform.treasury), // treasury balance
        platform.platform_fee_bps // platform fee
    )
}

// Admin functions
public entry fun update_platform_fee(
    platform: &mut Platform,
    new_fee_bps: u64,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == platform.admin, E_NOT_AUTHORIZED);
    assert!(new_fee_bps <= 1000, E_INVALID_STATUS); // Max 10%
    platform.platform_fee_bps = new_fee_bps;
}

public entry fun feature_bouty(
    platform: &mut Platform,
    bouty_id: u64,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == platform.admin, E_NOT_AUTHORIZED);
    assert!(table::contains(&platform.bouties, bouty_id), E_BOUTY_NOT_FOUND);
    
    let bouty = table::borrow_mut(&mut platform.bouties, bouty_id);
    bouty.is_featured = true;
}

public entry fun verify_user(
    platform: &mut Platform,
    user: address,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == platform.admin, E_NOT_AUTHORIZED);
    assert!(table::contains(&platform.user_profiles, user), E_NOT_AUTHORIZED);
    
    let profile = table::borrow_mut(&mut platform.user_profiles, user);
    profile.is_verified = true;
}

// Emergency functions
public entry fun cancel_bouty(
    platform: &mut Platform,
    bouty_id: u64,
    reason: String,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    assert!(table::contains(&platform.bouties, bouty_id), E_BOUTY_NOT_FOUND);

    let bouty = table::borrow_mut(&mut platform.bouties, bouty_id);
    assert!(bouty.creator == sender || sender == platform.admin, E_NOT_BOUTY_CREATOR);
    assert!(bouty.status == STATUS_OPEN || bouty.status == STATUS_IN_PROGRESS, E_INVALID_STATUS);

    bouty.status = STATUS_CANCELLED;

    // Refund the creator
    let refund_balance = balance::split(&mut platform.treasury, bouty.reward_base + bouty.bonus_reward);
    let refund_coin = coin::from_balance(refund_balance, ctx);
    transfer::public_transfer(refund_coin, bouty.creator);
}
}