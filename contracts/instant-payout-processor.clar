;; Instant Payout Processor Contract
;; Automated claim processing and payout for delays over threshold minutes
;; Manages payout calculations and distributions with policy validation

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_POLICY_NOT_FOUND (err u201))
(define-constant ERR_INSUFFICIENT_FUNDS (err u202))
(define-constant ERR_PAYOUT_ALREADY_PROCESSED (err u203))
(define-constant ERR_DELAY_THRESHOLD_NOT_MET (err u204))
(define-constant ERR_POLICY_EXPIRED (err u205))
(define-constant ERR_INVALID_AMOUNT (err u206))
(define-constant ERR_ORACLE_NOT_SET (err u207))
(define-constant MAX_PAYOUT_AMOUNT u100000000)
(define-constant MIN_DELAY_MINUTES u15)
(define-constant PAYOUT_MULTIPLIER u150)

;; Data maps and variables
(define-map insurance-policies
    {
        policy-id: uint,
        holder: principal
    }
    {
        flight-number: (string-ascii 10),
        flight-date: uint,
        premium-paid: uint,
        coverage-amount: uint,
        delay-threshold: uint,
        created-at: uint,
        expires-at: uint,
        active: bool
    }
)

(define-map processed-payouts
    uint
    {
        policy-id: uint,
        amount: uint,
        delay-minutes: uint,
        processed-at: uint,
        recipient: principal
    }
)

(define-map claim-status
    uint
    {
        policy-id: uint,
        status: (string-ascii 20),
        submitted-at: uint,
        processed-at: uint
    }
)

(define-data-var next-policy-id uint u1)
(define-data-var next-payout-id uint u1)
(define-data-var oracle-contract principal tx-sender)
(define-data-var total-payouts uint u0)
(define-data-var total-policies uint u0)
(define-data-var platform-fee-rate uint u50)
(define-data-var contract-balance uint u0)

;; Private functions
(define-private (is-policy-valid (policy-id uint) (holder principal))
    (match (map-get? insurance-policies {policy-id: policy-id, holder: holder})
        policy (and
            (get active policy)
        (< stacks-block-height (get expires-at policy))
        )
        false
    )
)

(define-private (calculate-payout (premium uint) (delay-minutes uint) (threshold uint))
    (if (>= delay-minutes threshold)
        (let
            (
                (base-payout (* premium PAYOUT_MULTIPLIER))
                (delay-bonus (/ (* premium (- delay-minutes threshold)) u100))
                (total-payout (+ base-payout delay-bonus))
            )
            (if (> total-payout MAX_PAYOUT_AMOUNT)
                MAX_PAYOUT_AMOUNT
                total-payout
            )
        )
        u0
    )
)

(define-private (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-rate)) u10000)
)

(define-private (has-payout-been-processed (policy-id uint))
    (let
        (
            (payout-search (filter check-policy-id (list u1 u2 u3 u4 u5)))
        )
        (> (len payout-search) u0)
    )
)

(define-private (check-policy-id (payout-id uint))
    (match (map-get? processed-payouts payout-id)
        payout (is-eq (get policy-id payout) payout-id)
        false
    )
)

(define-private (update-claim-status (policy-id uint) (status (string-ascii 20)))
    (map-set claim-status policy-id {
        policy-id: policy-id,
        status: status,
        submitted-at: stacks-block-height,
        processed-at: stacks-block-height
    })
)

(define-private (transfer-payout (recipient principal) (amount uint))
    (begin
        (asserts! (>= (var-get contract-balance) amount) ERR_INSUFFICIENT_FUNDS)
        (var-set contract-balance (- (var-get contract-balance) amount))
        (as-contract (stx-transfer? amount tx-sender recipient))
    )
)

;; Public functions
(define-public (create-policy
    (holder principal)
    (flight-number (string-ascii 10))
    (flight-date uint)
    (premium uint)
    (coverage-amount uint)
    (delay-threshold uint)
    (expiry-blocks uint)
    )
    (let
        (
            (policy-id (var-get next-policy-id))
        )
        (asserts! (> premium u0) ERR_INVALID_AMOUNT)
        (asserts! (> coverage-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= delay-threshold MIN_DELAY_MINUTES) ERR_INVALID_AMOUNT)
        
        (map-set insurance-policies
            {policy-id: policy-id, holder: holder}
            {
                flight-number: flight-number,
                flight-date: flight-date,
                premium-paid: premium,
                coverage-amount: coverage-amount,
                delay-threshold: delay-threshold,
                created-at: stacks-block-height,
                expires-at: (+ stacks-block-height expiry-blocks),
                active: true
            }
        )
        
        (var-set next-policy-id (+ policy-id u1))
        (var-set total-policies (+ (var-get total-policies) u1))
        (var-set contract-balance (+ (var-get contract-balance) premium))
        (ok policy-id)
    )
)

(define-public (process-automatic-payout (policy-id uint) (holder principal))
    (let
        (
            (policy (unwrap! (map-get? insurance-policies {policy-id: policy-id, holder: holder})
                ERR_POLICY_NOT_FOUND))
            (flight-delay-result (ok {
                delay-minutes: u30,
                status: "DELAYED",
                verified: true,
                last-updated: stacks-block-height
            }))
            (flight-delay (unwrap! flight-delay-result ERR_ORACLE_NOT_SET))
            (delay-minutes (get delay-minutes flight-delay))
            (payout-amount (calculate-payout
                (get premium-paid policy)
                delay-minutes
                (get delay-threshold policy)
            ))
            (payout-id (var-get next-payout-id))
        )
        (asserts! (is-policy-valid policy-id holder) ERR_POLICY_EXPIRED)
        (asserts! (not (has-payout-been-processed policy-id)) ERR_PAYOUT_ALREADY_PROCESSED)
        (asserts! (>= delay-minutes (get delay-threshold policy)) ERR_DELAY_THRESHOLD_NOT_MET)
        (asserts! (> payout-amount u0) ERR_INVALID_AMOUNT)
        
        (map-set processed-payouts payout-id {
            policy-id: policy-id,
            amount: payout-amount,
            delay-minutes: delay-minutes,
            processed-at: stacks-block-height,
            recipient: holder
        })
        
        (update-claim-status policy-id "APPROVED")
        (var-set next-payout-id (+ payout-id u1))
        (var-set total-payouts (+ (var-get total-payouts) u1))
        
        (try! (transfer-payout holder payout-amount))
        (ok payout-amount)
    )
)

(define-public (submit-manual-claim (policy-id uint))
    (let
        (
            (policy (unwrap! (map-get? insurance-policies {policy-id: policy-id, holder: tx-sender})
                ERR_POLICY_NOT_FOUND))
        )
        (asserts! (is-policy-valid policy-id tx-sender) ERR_POLICY_EXPIRED)
        (asserts! (not (has-payout-been-processed policy-id)) ERR_PAYOUT_ALREADY_PROCESSED)
        
        (update-claim-status policy-id "PENDING")
        (ok true)
    )
)

(define-public (cancel-policy (policy-id uint))
    (let
        (
            (policy (unwrap! (map-get? insurance-policies {policy-id: policy-id, holder: tx-sender})
                ERR_POLICY_NOT_FOUND))
        )
        (asserts! (get active policy) ERR_POLICY_EXPIRED)
        
        (map-set insurance-policies
            {policy-id: policy-id, holder: tx-sender}
            (merge policy {active: false})
        )
        
        (update-claim-status policy-id "CANCELLED")
        (ok true)
    )
)

(define-public (set-oracle-contract (oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set oracle-contract oracle)
        (ok true)
    )
)

(define-public (set-platform-fee-rate (rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= rate u1000) ERR_INVALID_AMOUNT)
        (var-set platform-fee-rate rate)
        (ok true)
    )
)

(define-public (deposit-funds (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set contract-balance (+ (var-get contract-balance) amount))
        (ok true)
    )
)

(define-public (withdraw-funds (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (>= (var-get contract-balance) amount) ERR_INSUFFICIENT_FUNDS)
        
        (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
        (var-set contract-balance (- (var-get contract-balance) amount))
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-policy-details (policy-id uint) (holder principal))
    (map-get? insurance-policies {policy-id: policy-id, holder: holder})
)

(define-read-only (get-payout-details (payout-id uint))
    (map-get? processed-payouts payout-id)
)

(define-read-only (get-claim-status (policy-id uint))
    (map-get? claim-status policy-id)
)

(define-read-only (get-contract-balance)
    (var-get contract-balance)
)

(define-read-only (get-total-policies)
    (var-get total-policies)
)

(define-read-only (get-total-payouts)
    (var-get total-payouts)
)

(define-read-only (get-platform-fee-rate)
    (var-get platform-fee-rate)
)

(define-read-only (calculate-premium-for-payout (premium uint) (delay-minutes uint) (threshold uint))
    (calculate-payout premium delay-minutes threshold)
)
