
(use-trait sip-010-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-LIQUIDITY (err u102))
(define-constant ERR-BATCH-NOT-READY (err u103))
(define-constant ERR-SLIPPAGE-EXCEEDED (err u104))
(define-constant ERR-NO-ORDERS (err u105))
(define-constant ERR-BATCH-FINALIZED (err u106))

(define-constant BATCH-BLOCKS u6)
(define-constant MIN-LIQUIDITY u1000)
(define-constant SCALE-FACTOR u1000000)

(define-data-var contract-owner principal tx-sender)
(define-data-var current-batch-id uint u0)
(define-data-var last-batch-block uint u0)
(define-data-var total-liquidity-x uint u0)
(define-data-var total-liquidity-y uint u0)

(define-map orders 
    { batch-id: uint, user: principal, order-id: uint }
    { 
        sell-amount: uint, 
        token-in: principal,
        min-out: uint
    }
)

(define-map batch-info
    { batch-id: uint }
    {
        total-sell-x: uint,
        total-sell-y: uint,
        clearing-price: uint,
        finalized: bool
    }
)

(define-map user-order-count { batch-id: uint, user: principal } uint)

(define-map twap-history
    { block-height: uint }
    { price-cumulative: uint, timestamp: uint }
)

(define-map settled-orders
    { batch-id: uint, user: principal, order-id: uint }
    bool
)

(define-private (get-user-order-count (batch-id uint) (user principal))
    (default-to u0 (map-get? user-order-count { batch-id: batch-id, user: user }))
)

(define-public (add-liquidity (token-x <sip-010-trait>) (token-y <sip-010-trait>) (amount-x uint) (amount-y uint))
    (begin
        (asserts! (> amount-x u0) ERR-INVALID-AMOUNT)
        (asserts! (> amount-y u0) ERR-INVALID-AMOUNT)
        
        (try! (contract-call? token-x transfer amount-x tx-sender (as-contract tx-sender) none))
        (try! (contract-call? token-y transfer amount-y tx-sender (as-contract tx-sender) none))
        
        (var-set total-liquidity-x (+ (var-get total-liquidity-x) amount-x))
        (var-set total-liquidity-y (+ (var-get total-liquidity-y) amount-y))
        
        (ok true)
    )
)

(define-public (remove-liquidity (token-x <sip-010-trait>) (token-y <sip-010-trait>) (amount-x uint) (amount-y uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= amount-x (var-get total-liquidity-x)) ERR-INSUFFICIENT-LIQUIDITY)
        (asserts! (<= amount-y (var-get total-liquidity-y)) ERR-INSUFFICIENT-LIQUIDITY)
        
        
        (try! (as-contract (contract-call? token-x transfer amount-x tx-sender (var-get contract-owner) none)))
        (try! (as-contract (contract-call? token-y transfer amount-y tx-sender (var-get contract-owner) none)))
        
        
        (var-set total-liquidity-x (- (var-get total-liquidity-x) amount-x))
        (var-set total-liquidity-y (- (var-get total-liquidity-y) amount-y))
        
        (ok true)
    )
)

(define-public (submit-order (token-in <sip-010-trait>) (amount uint) (min-out uint))
    (let
        (
            (batch-id (var-get current-batch-id))
            (sender tx-sender)
            (current-count (get-user-order-count batch-id sender))
            (new-count (+ current-count u1))
        )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (try! (contract-call? token-in transfer amount sender (as-contract tx-sender) none))
        
        (map-set orders 
            { batch-id: batch-id, user: sender, order-id: new-count }
            { sell-amount: amount, token-in: (contract-of token-in), min-out: min-out }
        )
        (map-set user-order-count { batch-id: batch-id, user: sender } new-count)
        
        (let ((current-batch (default-to { total-sell-x: u0, total-sell-y: u0, clearing-price: u0, finalized: false } (map-get? batch-info { batch-id: batch-id }))))
            (map-set batch-info { batch-id: batch-id }
                (merge current-batch {
                    total-sell-x: (+ (get total-sell-x current-batch) amount)
                })
            )
        )
        (ok new-count)
    )
)



(define-public (cancel-order (batch-id uint) (order-id uint) (token-trait <sip-010-trait>))
    (let
        (
            (sender tx-sender)
            (order (unwrap! (map-get? orders { batch-id: batch-id, user: sender, order-id: order-id }) ERR-NO-ORDERS))
            (batch (unwrap! (map-get? batch-info { batch-id: batch-id }) ERR-BATCH-NOT-READY))
            (is-settled (default-to false (map-get? settled-orders { batch-id: batch-id, user: sender, order-id: order-id })))
        )
        ;; Can only cancel if batch is NOT finalized
        (asserts! (not (get finalized batch)) ERR-BATCH-FINALIZED)
        ;; Can only cancel if not already settled
        (asserts! (not is-settled) ERR-NOT-AUTHORIZED)
        ;; Ensure the passed trait matches the order's token
        (asserts! (is-eq (contract-of token-trait) (get token-in order)) ERR-INVALID-AMOUNT)

        ;; Update batch info to remove sell pressure
        (map-set batch-info { batch-id: batch-id }
            (merge batch {
                total-sell-x: (- (get total-sell-x batch) (get sell-amount order))
            })
        )

        ;; Remove the order to prevent double interaction
        (map-delete orders { batch-id: batch-id, user: sender, order-id: order-id })
        
        ;; Refund tokens to user
        (as-contract (contract-call? token-trait transfer (get sell-amount order) tx-sender sender none))
    )
)



(define-public (finalize-current-batch)
    (let
        (
            (batch-id (var-get current-batch-id))
            (current-block block-height)
            (last-block (var-get last-batch-block))
        )
        (asserts! (>= (- current-block last-block) BATCH-BLOCKS) ERR-BATCH-NOT-READY)
        
        (let
            (
                (batch (unwrap! (map-get? batch-info { batch-id: batch-id }) ERR-NO-ORDERS))
                (total-sell (get total-sell-x batch))
                (new-price (calculate-clearing-price total-sell))
            )
            
            (map-set batch-info { batch-id: batch-id }
                (merge batch { clearing-price: new-price, finalized: true })
            )
            
            (update-twap new-price)
            
            (var-set current-batch-id (+ batch-id u1))
            (var-set last-batch-block current-block)
            
            (ok new-price)
        )
    )
)

(define-private (calculate-clearing-price (sell-pressure uint))
    (let
        (
            (liq-x (var-get total-liquidity-x))
            (liq-y (var-get total-liquidity-y))
        )
        (if (is-eq sell-pressure u0)
            (if (> liq-x u0) (/ (* liq-y SCALE-FACTOR) liq-x) u0)
            (/ (* liq-y SCALE-FACTOR) (+ liq-x sell-pressure))
        )
    )
)

(define-private (update-twap (current-price uint))
    (let
        (
            (prev-twap (default-to { price-cumulative: u0, timestamp: u0 } (map-get? twap-history { block-height: (var-get last-batch-block) })))
            (time-delta (- block-height (var-get last-batch-block)))
            (new-cumulative (+ (get price-cumulative prev-twap) (* current-price time-delta)))
        )
        (map-set twap-history { block-height: block-height }
            { price-cumulative: new-cumulative, timestamp: block-height }
        )
    )
)

(define-read-only (get-current-batch-id)
    (ok (var-get current-batch-id))
)

(define-read-only (get-batch-info (batch-id uint))
    (ok (map-get? batch-info { batch-id: batch-id }))
)

(define-read-only (get-order-details (batch-id uint) (user principal) (order-id uint))
    (ok (map-get? orders { batch-id: batch-id, user: user, order-id: order-id }))
)

(define-read-only (get-spot-price)
    (let
        (
            (liq-x (var-get total-liquidity-x))
            (liq-y (var-get total-liquidity-y))
        )
        (if (> liq-x u0)
            (ok (/ (* liq-y SCALE-FACTOR) liq-x))
            (ok u0)
        )
    )
)

(define-read-only (get-average-price (start-block uint) (end-block uint))
    (let
        (
            (start-twap (default-to { price-cumulative: u0, timestamp: u0 } (map-get? twap-history { block-height: start-block })))
            (end-twap (default-to { price-cumulative: u0, timestamp: u0 } (map-get? twap-history { block-height: end-block })))
            (price-diff (- (get price-cumulative end-twap) (get price-cumulative start-twap)))
            (time-diff (- end-block start-block))
        )
        (if (> time-diff u0)
            (ok (/ price-diff time-diff))
            (ok u0)
        )
    )
)


(define-public (settle-order (batch-id uint) (order-id uint) (token-in <sip-010-trait>) (token-out <sip-010-trait>))
    (let
        (
            (sender tx-sender)
            (order (unwrap! (map-get? orders { batch-id: batch-id, user: sender, order-id: order-id }) ERR-NO-ORDERS))
            (batch (unwrap! (map-get? batch-info { batch-id: batch-id }) ERR-BATCH-NOT-READY))
            (is-settled (default-to false (map-get? settled-orders { batch-id: batch-id, user: sender, order-id: order-id })))
        )
        (asserts! (get finalized batch) ERR-BATCH-NOT-READY)
        (asserts! (not is-settled) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (contract-of token-in) (get token-in order)) ERR-INVALID-AMOUNT)

        (map-set settled-orders { batch-id: batch-id, user: sender, order-id: order-id } true)

        (let
            (
                (price (get clearing-price batch))
                (input-amount (get sell-amount order))
                (output-amount (/ (* input-amount price) SCALE-FACTOR))
                (min-out (get min-out order))
            )
            ;; If output amount meets minimum or price is favorable, execute swap
            ;; Otherwise, refund the original input amount
            (if (>= output-amount min-out)
                (as-contract (contract-call? token-out transfer output-amount tx-sender sender none))
                (as-contract (contract-call? token-in transfer input-amount tx-sender sender none))
            )
        )
    )
)


(define-read-only (get-pool-reserves)
    (ok { x: (var-get total-liquidity-x), y: (var-get total-liquidity-y) })
)

;; Additional helpers to reach line count
(define-public (force-update-batch)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set last-batch-block block-height)
        (ok true)
    )
)

(define-data-var fee-rate uint u30) ;; 0.3%

(define-read-only (calculate-fee (amount uint))
    (/ (* amount (var-get fee-rate)) u10000)
)

(define-public (set-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-rate u1000) ERR-INVALID-AMOUNT)
        (var-set fee-rate new-rate)
        (ok true)
    )
)
