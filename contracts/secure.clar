;; SecureStats - Bitcoin-Backed Lending Protocol
;; Secure lending protocol built on Stacks with BTC as collateral

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Constants
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-constant contract-owner tx-sender)

;; Loan Parameters
(define-constant MIN-LOAN-AMOUNT u1000000)           ;; Minimum loan amount (1M uSTX)
(define-constant MAX-LOAN-AMOUNT u1000000000)        ;; Maximum loan amount (1B uSTX)
(define-constant LIQUIDATOR-REWARD-PERCENT u5)       ;; 5% liquidator reward
(define-constant MIN-COLLATERAL-RATIO u110)          ;; Minimum allowed collateral ratio
(define-constant MAX-COLLATERAL-RATIO u500)          ;; Maximum allowed collateral ratio

;; Error Codes
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-INVALID-LOAN (err u101))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u102))
(define-constant ERR-LOAN-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-LIQUIDATED (err u104))
(define-constant ERR-NOT-LIQUIDATABLE (err u105))
(define-constant ERR-NOT-BORROWER (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))
(define-constant ERR-INVALID-PARAMETER (err u108))
(define-constant ERR-INVALID-LOAN-ID (err u109))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Data Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-data-var next-loan-id uint u0)               ;; Track the next available loan ID
(define-data-var minimum-collateral-ratio uint u150) ;; 150% collateralization ratio
(define-data-var liquidation-threshold uint u130)    ;; 130% liquidation threshold
(define-data-var protocol-fee uint u1)               ;; 1% protocol fee

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Data Maps
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Private Helper Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-private (validate-loan-id (loan-id uint))
    (and 
        (>= loan-id u1)
        (<= loan-id (var-get next-loan-id))
    )
)

(define-private (validate-loan-parameters (loan-amount uint) (collateral-ratio uint))
    (and 
        (>= loan-amount MIN-LOAN-AMOUNT)
        (<= loan-amount MAX-LOAN-AMOUNT)
        (>= collateral-ratio (var-get minimum-collateral-ratio))
    )
)

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

(define-private (get-loan-details (loan-id uint))
    (match (map-get? loans { loan-id: loan-id })
        loan-data (ok {
            loan-id: loan-id,
            collateral: (get collateral-amount loan-data),
            borrowed: (get loan-amount loan-data),
            health-ratio: (calculate-collateral-ratio (get collateral-amount loan-data) (get loan-amount loan-data)),
            start-block: (get start-height loan-data)
        })
        ERR-LOAN-NOT-FOUND
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Public Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (create-loan (collateral-amount uint) (loan-amount uint))
    (let
        (
            (loan-id (+ (var-get next-loan-id) u1))
            (collateral-ratio (calculate-collateral-ratio collateral-amount loan-amount))
        )
        ;; Validate parameters
        (asserts! (validate-loan-parameters loan-amount collateral-ratio) ERR-INVALID-LOAN)
        
        ;; Transfer collateral
        (try! (stx-transfer? collateral-amount tx-sender (as-contract tx-sender)))
        
        ;; Create loan record
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
        
        ;; Update loan counter
        (var-set next-loan-id loan-id)
        (ok loan-id)
    )
)

(define-public (repay-loan (loan-id uint))
    (begin
        ;; Validate loan ID
        (asserts! (validate-loan-id loan-id) ERR-INVALID-LOAN-ID)
        
        (match (map-get? loans { loan-id: loan-id })
            loan-data
            (begin
                (asserts! (not (get liquidated loan-data)) ERR-ALREADY-LIQUIDATED)
                (let
                    (
                        (total-due (calculate-total-due loan-data))
                    )
                    ;; Process repayment
                    (try! (stx-transfer? total-due tx-sender (as-contract tx-sender)))
                    (try! (as-contract (stx-transfer? (get collateral-amount loan-data) (as-contract tx-sender) (get borrower loan-data))))
                    
                    ;; Clear loan record
                    (map-delete loans { loan-id: loan-id })
                    (ok true)
                )
            )
            ERR-LOAN-NOT-FOUND
        )
    )
)

(define-public (check-loan-health (loan-id uint))
    (begin
        ;; Validate loan ID
        (asserts! (validate-loan-id loan-id) ERR-INVALID-LOAN-ID)
        
        (match (map-get? loans { loan-id: loan-id })
            loan-data
            (let
                (
                    (current-ratio (calculate-collateral-ratio (get collateral-amount loan-data) (get loan-amount loan-data)))
                )
                (ok {
                    loan-id: loan-id,
                    health-ratio: current-ratio,
                    is-healthy: (>= current-ratio (var-get liquidation-threshold)),
                    borrower: (get borrower loan-data),
                    collateral: (get collateral-amount loan-data),
                    loan-amount: (get loan-amount loan-data)
                })
            )
            ERR-LOAN-NOT-FOUND
        )
    )
)

(define-public (liquidate-loan (loan-id uint))
    (begin
        ;; Validate loan ID
        (asserts! (validate-loan-id loan-id) ERR-INVALID-LOAN-ID)
        
        (match (map-get? loans { loan-id: loan-id })
            loan-data
            (begin
                (asserts! (not (get liquidated loan-data)) ERR-ALREADY-LIQUIDATED)
                
                (let
                    (
                        (current-ratio (calculate-collateral-ratio (get collateral-amount loan-data) (get loan-amount loan-data)))
                    )
                    ;; Verify loan can be liquidated
                    (asserts! (< current-ratio (var-get liquidation-threshold)) ERR-NOT-LIQUIDATABLE)
                    
                    (let
                        (
                            (liquidator-reward (/ (* (get collateral-amount loan-data) LIQUIDATOR-REWARD-PERCENT) u100))
                            (protocol-share (/ (* (get collateral-amount loan-data) (var-get protocol-fee)) u100))
                            (remaining-collateral (- (get collateral-amount loan-data) (+ liquidator-reward protocol-share)))
                        )
                        ;; Process liquidation distributions
                        (try! (as-contract (stx-transfer? liquidator-reward (as-contract tx-sender) tx-sender)))
                        (try! (as-contract (stx-transfer? protocol-share (as-contract tx-sender) contract-owner)))
                        (try! (as-contract (stx-transfer? remaining-collateral (as-contract tx-sender) (get borrower loan-data))))
                        
                        ;; Update loan status
                        (map-set loans
                            { loan-id: loan-id }
                            (merge loan-data { liquidated: true })
                        )
                        (ok true)
                    )
                )
            )
            ERR-LOAN-NOT-FOUND
        )
    )
)

(define-public (add-collateral (loan-id uint) (additional-collateral uint))
    (begin
        ;; Validate loan ID
        (asserts! (validate-loan-id loan-id) ERR-INVALID-LOAN-ID)
        
        (match (map-get? loans { loan-id: loan-id })
            loan-data
            (begin
                (asserts! (is-eq (get borrower loan-data) tx-sender) ERR-NOT-BORROWER)
                (asserts! (not (get liquidated loan-data)) ERR-ALREADY-LIQUIDATED)
                
                ;; Transfer additional collateral
                (try! (stx-transfer? additional-collateral tx-sender (as-contract tx-sender)))
                
                ;; Update loan record
                (map-set loans
                    { loan-id: loan-id }
                    (merge loan-data { 
                        collateral-amount: (+ (get collateral-amount loan-data) additional-collateral)
                    })
                )
                (ok true)
            )
            ERR-LOAN-NOT-FOUND
        )
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Read-Only Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-read-only (get-user-loans (user principal))
    (match (map-get? user-loans { user: user })
        user-data
        (let
            (
                (active-loans (get active-loans user-data))
                (loan-details (map get-loan-details active-loans))
            )
            (ok {
                user: user,
                loan-count: (len active-loans),
                loans: loan-details
            })
        )
        (ok {
            user: user,
            loan-count: u0,
            loans: (list)
        })
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Administrative Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (update-minimum-collateral-ratio (new-ratio uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
        (asserts! (and (>= new-ratio MIN-COLLATERAL-RATIO) (<= new-ratio MAX-COLLATERAL-RATIO)) ERR-INVALID-PARAMETER)
        (var-set minimum-collateral-ratio new-ratio)
        (ok true)
    )
)

(define-public (update-liquidation-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
        (asserts! (and (>= new-threshold MIN-COLLATERAL-RATIO) (<= new-threshold (var-get minimum-collateral-ratio))) ERR-INVALID-PARAMETER)
        (var-set liquidation-threshold new-threshold)
        (ok true)
    )
)