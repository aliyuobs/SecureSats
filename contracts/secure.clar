;; SecureStats - Bitcoin-Backed Lending Protocol
;; A decentralized lending protocol built on Stacks

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-collateral (err u101))
(define-constant err-loan-not-found (err u102))
(define-constant err-already-liquidated (err u103))

;; Data Variables
(define-data-var next-loan-id uint u0)               ;; Track the next available loan ID
(define-data-var minimum-collateral-ratio uint u150) ;; 150% collateralization ratio
(define-data-var liquidation-threshold uint u130)    ;; 130% liquidation threshold
(define-data-var protocol-fee uint u1)               ;; 1% protocol fee

;; Data Maps
(define-map loans
    { loan-id: uint }
    {
        borrower: principal,
        collateral-amount: uint,
        loan-amount: uint,
        interest-rate: uint,
        start-height: uint,
        liquidated: bool
    }
)

(define-map user-loans
    { user: principal }
    { active-loans: (list 10 uint) }
)

;; Public Functions
(define-public (create-loan (collateral-amount uint) (loan-amount uint))
    (let
        (
            (loan-id (+ (var-get next-loan-id) u1))
            (collateral-ratio (calculate-collateral-ratio collateral-amount loan-amount))
        )
        (asserts! (>= collateral-ratio (var-get minimum-collateral-ratio)) err-insufficient-collateral)
        (try! (stx-transfer? collateral-amount tx-sender (as-contract tx-sender)))
        (map-set loans
            { loan-id: loan-id }
            {
                borrower: tx-sender,
                collateral-amount: collateral-amount,
                loan-amount: loan-amount,
                interest-rate: (calculate-interest-rate loan-amount collateral-ratio),
                start-height: block-height,
                liquidated: false
            }
        )
        (var-set next-loan-id loan-id)
        (ok loan-id)
    )
)

(define-public (repay-loan (loan-id uint))
    (let
        (
            (loan (unwrap! (map-get? loans { loan-id: loan-id }) err-loan-not-found))
            (total-due (calculate-total-due loan))
        )
        (asserts! (not (get liquidated loan)) err-already-liquidated)
        (try! (stx-transfer? total-due tx-sender (as-contract tx-sender)))
        (try! (as-contract (stx-transfer? (get collateral-amount loan) (as-contract tx-sender) (get borrower loan))))
        (map-delete loans { loan-id: loan-id })
        (ok true)
    )
)

;; Private Functions
(define-private (calculate-collateral-ratio (collateral uint) (loan uint))
    (/ (* collateral u100) loan)
)

(define-private (calculate-interest-rate (loan-amount uint) (collateral-ratio uint))
    (let
        (
            (base-rate u5)  ;; 5% base rate
            (ratio-bonus (/ u100 collateral-ratio))
        )
        (+ base-rate ratio-bonus)
    )
)

(define-private (calculate-total-due (loan { borrower: principal, collateral-amount: uint, loan-amount: uint, interest-rate: uint, start-height: uint, liquidated: bool }))
    (let
        (
            (duration (- block-height (get start-height loan)))
            (interest-amount (/ (* (get loan-amount loan) (get interest-rate loan) duration) u10000))
        )
        (+ (get loan-amount loan) interest-amount)
    )
)

;; Loan Health and Liquidation Functions
(define-public (check-loan-health (loan-id uint))
    (let
        (
            (loan (unwrap! (map-get? loans { loan-id: loan-id }) err-loan-not-found))
            (current-ratio (calculate-collateral-ratio (get collateral-amount loan) (get loan-amount loan)))
        )
        (ok {
            loan-id: loan-id,
            health-ratio: current-ratio,
            is-healthy: (>= current-ratio (var-get liquidation-threshold)),
            borrower: (get borrower loan),
            collateral: (get collateral-amount loan),
            loan-amount: (get loan-amount loan)
        })
    )
)

(define-public (liquidate-loan (loan-id uint))
    (let
        (
            (loan (unwrap! (map-get? loans { loan-id: loan-id }) err-loan-not-found))
            (current-ratio (calculate-collateral-ratio (get collateral-amount loan) (get loan-amount loan)))
        )
        (asserts! (not (get liquidated loan)) err-already-liquidated)
        (asserts! (< current-ratio (var-get liquidation-threshold)) (err u104)) ;; err-not-liquidatable
        
        ;; Calculate liquidation reward (5% of collateral)
        (let
            (
                (liquidator-reward (/ (* (get collateral-amount loan) u5) u100))
                (protocol-share (/ (* (get collateral-amount loan) (var-get protocol-fee)) u100))
                (remaining-collateral (- (get collateral-amount loan) (+ liquidator-reward protocol-share)))
            )
            ;; Transfer liquidation reward to liquidator
            (try! (as-contract (stx-transfer? liquidator-reward (as-contract tx-sender) tx-sender)))
            ;; Transfer protocol fee
            (try! (as-contract (stx-transfer? protocol-share (as-contract tx-sender) contract-owner)))
            ;; Return remaining collateral to borrower
            (try! (as-contract (stx-transfer? remaining-collateral (as-contract tx-sender) (get borrower loan))))
            
            ;; Update loan status
            (map-set loans
                { loan-id: loan-id }
                (merge loan { liquidated: true })
            )
            (ok true)
        )
    )
)

;; Additional Utility Functions
(define-read-only (get-user-loans (user principal))
    (let
        (
            (user-loan-ids (default-to { active-loans: (list) } (map-get? user-loans { user: user })))
            (active-loan-count (len (get active-loans user-loan-ids)))
        )
        (ok {
            user: user,
            loan-count: active-loan-count,
            loans: (map get-loan-details (get active-loans user-loan-ids))
        })
    )
)

(define-private (get-loan-details (loan-id uint))
    (let
        (
            (loan (unwrap-panic (map-get? loans { loan-id: loan-id })))
        )
        {
            loan-id: loan-id,
            collateral: (get collateral-amount loan),
            borrowed: (get loan-amount loan),
            health-ratio: (calculate-collateral-ratio (get collateral-amount loan) (get loan-amount loan)),
            start-block: (get start-height loan)
        }
    )
)

(define-public (add-collateral (loan-id uint) (additional-collateral uint))
    (let
        (
            (loan (unwrap! (map-get? loans { loan-id: loan-id }) err-loan-not-found))
        )
        (asserts! (is-eq (get borrower loan) tx-sender) (err u105)) ;; err-not-borrower
        (asserts! (not (get liquidated loan)) err-already-liquidated)
        
        ;; Transfer additional collateral
        (try! (stx-transfer? additional-collateral tx-sender (as-contract tx-sender)))
        
        ;; Update loan collateral amount
        (map-set loans
            { loan-id: loan-id }
            (merge loan { 
                collateral-amount: (+ (get collateral-amount loan) additional-collateral)
            })
        )
        
        (ok true)
    )
)

;; Administrative Functions
(define-public (update-minimum-collateral-ratio (new-ratio uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set minimum-collateral-ratio new-ratio)
        (ok true)
    )
)

(define-public (update-liquidation-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set liquidation-threshold new-threshold)
        (ok true)
    )
)