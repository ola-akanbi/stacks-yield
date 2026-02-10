;; Title: Stacks Yield
;;
;; Summary:
;; A secure and compliant DeFi protocol enabling efficient Bitcoin yield optimization 
;; on Stacks Layer 2, with institutional-grade security and comprehensive risk management.

;; Constants
(define-constant contract-owner tx-sender)

;; Time-Weighted Deposit Constants
(define-constant MIN-WEIGHT u2500)
(define-constant MAX-WEIGHT u10000)
(define-constant WEIGHT-RAMP-BLOCKS u2016)

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-AMOUNT (err u1001))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1002))
(define-constant ERR-PROTOCOL-NOT-WHITELISTED (err u1003))
(define-constant ERR-STRATEGY-DISABLED (err u1004))
(define-constant ERR-MAX-DEPOSIT-REACHED (err u1005))
(define-constant ERR-MIN-DEPOSIT-NOT-MET (err u1006))
(define-constant ERR-INVALID-PROTOCOL-ID (err u1007))
(define-constant ERR-PROTOCOL-EXISTS (err u1008))
(define-constant ERR-INVALID-APY (err u1009))
(define-constant ERR-INVALID-NAME (err u1010))
(define-constant ERR-INVALID-TOKEN (err u1011))
(define-constant ERR-TOKEN-NOT-WHITELISTED (err u1012))
(define-constant ERR-ZERO-AMOUNT (err u1013))
(define-constant ERR-INVALID-USER (err u1014))
(define-constant ERR-ALREADY-WHITELISTED (err u1015))
(define-constant ERR-AMOUNT-TOO-LARGE (err u1016))
(define-constant ERR-INVALID-STATE (err u1017))
(define-constant ERR-RATE-LIMITED (err u1018))

;; Protocol Constants
(define-constant PROTOCOL-ACTIVE true)
(define-constant MAX-PROTOCOL-ID u100)
(define-constant MAX-APY u10000)
(define-constant MIN-APY u0)
(define-constant MAX-TOKEN-TRANSFER u1000000000000)

;; State Variables
(define-data-var total-tvl uint u0)
(define-data-var platform-fee-rate uint u100)
(define-data-var min-deposit uint u100000)
(define-data-var max-deposit uint u1000000000)
(define-data-var emergency-shutdown bool false)

;; Data Maps
(define-map user-deposits
    { user: principal }
    { amount: uint, last-deposit-block: uint, weighted-entry-block: uint }
)

(define-map user-rewards
    { user: principal }
    { pending: uint, claimed: uint }
)

(define-map protocols
    { protocol-id: uint }
    { name: (string-ascii 64), active: bool, apy: uint }
)

(define-map strategy-allocations
    { protocol-id: uint }
    { allocation: uint }
)

(define-map whitelisted-tokens
    { token: principal }
    { approved: bool }
)

(define-map user-operations
    { user: principal }
    { last-operation: uint, count: uint }
)

;; SIP-010 Trait
(define-trait sip-010-trait
    (
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))
        (get-balance (principal) (response uint uint))
        (get-decimals () (response uint uint))
        (get-name () (response (string-ascii 32) uint))
        (get-symbol () (response (string-ascii 32) uint))
        (get-total-supply () (response uint uint))
    )
)

;; Authorization
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)

;; Helpers
(define-private (get-time-weight (entry-block uint))
    (let (
        (elapsed (- stacks-block-height entry-block))
        (weight (+ MIN-WEIGHT
            (/ (* elapsed (- MAX-WEIGHT MIN-WEIGHT)) WEIGHT-RAMP-BLOCKS)))
    )
        (min weight MAX-WEIGHT)
    )
)

(define-private (blend-entry-block (old-block uint) (old-amount uint) (new-amount uint))
    (/ (+ (* old-block old-amount)
          (* stacks-block-height new-amount))
       (+ old-amount new-amount))
)

;; Deposit
(define-public (deposit (token <sip-010-trait>) (amount uint))
    (let (
        (user tx-sender)
        (current
            (default-to
                { amount: u0, last-deposit-block: u0, weighted-entry-block: u0 }
                (map-get? user-deposits { user: user })))
    )
        (asserts! (> amount u0) ERR-ZERO-AMOUNT)
        (asserts! (>= amount (var-get min-deposit)) ERR-MIN-DEPOSIT-NOT-MET)
        (asserts! (<= (+ amount (get amount current)) (var-get max-deposit)) ERR-MAX-DEPOSIT-REACHED)
        (asserts! (not (var-get emergency-shutdown)) ERR-STRATEGY-DISABLED)

        (let (
            (entry
                (if (> (get amount current) u0)
                    (blend-entry-block
                        (get weighted-entry-block current)
                        (get amount current)
                        amount)
                    stacks-block-height))
        )
            (map-set user-deposits
                { user: user }
                {
                    amount: (+ amount (get amount current)),
                    last-deposit-block: stacks-block-height,
                    weighted-entry-block: entry
                }
            )
        )

        (var-set total-tvl (+ (var-get total-tvl) amount))
        (ok true)
    )
)

;; Withdraw
(define-public (withdraw (token <sip-010-trait>) (amount uint))
    (let (
        (user tx-sender)
        (current (unwrap-panic (map-get? user-deposits { user: user })))
    )
        (asserts! (<= amount (get amount current)) ERR-INSUFFICIENT-BALANCE)

        (map-set user-deposits
            { user: user }
            {
                amount: (- (get amount current) amount),
                last-deposit-block: (get last-deposit-block current),
                weighted-entry-block:
                    (if (= (- (get amount current) amount) u0)
                        u0
                        (get weighted-entry-block current))
            }
        )

        (var-set total-tvl (- (var-get total-tvl) amount))
        (ok true)
    )
)

;; Rewards
(define-private (calculate-rewards (user principal) (blocks uint))
    (let (
        (deposit (unwrap-panic (map-get? user-deposits { user: user })))
        (weight (get-time-weight (get weighted-entry-block deposit)))
    )
        (/ (* (get amount deposit)
              blocks
              weight)
           (* u10000 u144))
    )
)
