;; Dutch Auction Smart Contract
;; Supports auctions where price decreases over time until a bid is placed

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-AUCTION-NOT-FOUND (err u101))
(define-constant ERR-AUCTION-ENDED (err u102))
(define-constant ERR-AUCTION-NOT-STARTED (err u103))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u104))
(define-constant ERR-AUCTION-ALREADY-EXISTS (err u105))
(define-constant ERR-INVALID-PARAMETERS (err u106))
(define-constant ERR-TRANSFER-FAILED (err u107))
(define-constant ERR-AUCTION-ACTIVE (err u108))
(define-constant ERR-NO-WINNER (err u109))
(define-constant ERR-ALREADY-CLAIMED (err u110))

;; Data Variables
(define-data-var next-auction-id uint u1)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points

;; Data Maps
(define-map auctions
  uint
  {
    seller: principal,
    item-id: uint,
    start-price: uint,
    end-price: uint,
    start-block: uint,
    duration-blocks: uint,
    winner: (optional principal),
    winning-price: (optional uint),
    claimed: bool,
    active: bool
  }
)

(define-map auction-items
  uint
  {
    name: (string-ascii 64),
    description: (string-ascii 256),
    image-url: (optional (string-ascii 256))
  }
)

(define-map user-auction-count principal uint)

;; Read-only functions

(define-read-only (get-auction (auction-id uint))
  (map-get? auctions auction-id)
)

(define-read-only (get-auction-item (item-id uint))
  (map-get? auction-items item-id)
)

(define-read-only (get-current-price (auction-id uint))
  (let (
    (auction (unwrap! (map-get? auctions auction-id) ERR-AUCTION-NOT-FOUND))
    (current-block block-height)
    (start-block (get start-block auction))
    (duration (get duration-blocks auction))
    (start-price (get start-price auction))
    (end-price (get end-price auction))
  )
    (if (< current-block start-block)
      ;; Auction hasn't started yet
      (ok start-price)
      (if (>= current-block (+ start-block duration))
        ;; Auction has ended
        (ok end-price)
        ;; Calculate current price based on linear decrease
        (let (
          (blocks-elapsed (- current-block start-block))
          (price-difference (- start-price end-price))
          (price-decrease (/ (* price-difference blocks-elapsed) duration))
        )
          (ok (- start-price price-decrease))
        )
      )
    )
  )
)

(define-read-only (is-auction-active (auction-id uint))
  (let (
    (auction (unwrap! (map-get? auctions auction-id) false))
    (current-block block-height)
    (start-block (get start-block auction))
    (duration (get duration-blocks auction))
  )
    (and 
      (get active auction)
      (>= current-block start-block)
      (< current-block (+ start-block duration))
      (is-none (get winner auction))
    )
  )
)

(define-read-only (get-user-auction-count (user principal))
  (default-to u0 (map-get? user-auction-count user))
)

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

;; Public functions

(define-public (create-auction 
  (item-name (string-ascii 64))
  (item-description (string-ascii 256))
  (item-image-url (optional (string-ascii 256)))
  (start-price uint)
  (end-price uint)
  (duration-blocks uint)
  (start-delay-blocks uint)
)
  (let (
    (auction-id (var-get next-auction-id))
    (item-id auction-id)
    (start-block (+ block-height start-delay-blocks))
  )
    ;; Validate parameters
    (asserts! (> start-price end-price) ERR-INVALID-PARAMETERS)
    (asserts! (> duration-blocks u0) ERR-INVALID-PARAMETERS)
    (asserts! (> start-price u0) ERR-INVALID-PARAMETERS)
    
    ;; Create auction item
    (map-set auction-items item-id {
      name: item-name,
      description: item-description,
      image-url: item-image-url
    })
    
    ;; Create auction
    (map-set auctions auction-id {
      seller: tx-sender,
      item-id: item-id,
      start-price: start-price,
      end-price: end-price,
      start-block: start-block,
      duration-blocks: duration-blocks,
      winner: none,
      winning-price: none,
      claimed: false,
      active: true
    })
    
    ;; Update counters
    (var-set next-auction-id (+ auction-id u1))
    (map-set user-auction-count tx-sender 
      (+ (get-user-auction-count tx-sender) u1))
    
    (ok auction-id)
  )
)

(define-public (place-bid (auction-id uint))
  (let (
    (auction (unwrap! (map-get? auctions auction-id) ERR-AUCTION-NOT-FOUND))
    (current-price (unwrap! (get-current-price auction-id) ERR-AUCTION-NOT-FOUND))
    (seller (get seller auction))
    (platform-fee (/ (* current-price (var-get platform-fee-rate)) u10000))
    (seller-amount (- current-price platform-fee))
  )
    ;; Validate auction is active
    (asserts! (is-auction-active auction-id) ERR-AUCTION-ENDED)
    
    ;; Transfer payment from bidder
    (try! (stx-transfer? current-price tx-sender (as-contract tx-sender)))
    
    ;; Transfer to seller (minus platform fee)
    (try! (as-contract (stx-transfer? seller-amount tx-sender seller)))
    
    ;; Platform fee stays in contract
    
    ;; Update auction with winner
    (map-set auctions auction-id (merge auction {
      winner: (some tx-sender),
      winning-price: (some current-price),
      active: false
    }))
    
    (ok {
      winner: tx-sender,
      winning-price: current-price,
      platform-fee: platform-fee
    })
  )
)

(define-public (cancel-auction (auction-id uint))
  (let (
    (auction (unwrap! (map-get? auctions auction-id) ERR-AUCTION-NOT-FOUND))
  )
    ;; Only seller can cancel
    (asserts! (is-eq tx-sender (get seller auction)) ERR-NOT-AUTHORIZED)
    
    ;; Can only cancel if no winner yet
    (asserts! (is-none (get winner auction)) ERR-AUCTION-ENDED)
    
    ;; Mark as inactive
    (map-set auctions auction-id (merge auction {
      active: false
    }))
    
    (ok true)
  )
)

(define-public (extend-auction (auction-id uint) (additional-blocks uint))
  (let (
    (auction (unwrap! (map-get? auctions auction-id) ERR-AUCTION-NOT-FOUND))
  )
    ;; Only seller can extend
    (asserts! (is-eq tx-sender (get seller auction)) ERR-NOT-AUTHORIZED)
    
    ;; Can only extend active auctions without winners
    (asserts! (get active auction) ERR-AUCTION-ENDED)
    (asserts! (is-none (get winner auction)) ERR-AUCTION-ENDED)
    
    ;; Update duration
    (map-set auctions auction-id (merge auction {
      duration-blocks: (+ (get duration-blocks auction) additional-blocks)
    }))
    
    (ok true)
  )
)

;; Admin functions

(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-rate u1000) ERR-INVALID-PARAMETERS) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

(define-public (withdraw-platform-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
    (ok true)
  )
)

;; Emergency functions

(define-public (emergency-cancel-auction (auction-id uint))
  (let (
    (auction (unwrap! (map-get? auctions auction-id) ERR-AUCTION-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    ;; Mark as inactive
    (map-set auctions auction-id (merge auction {
      active: false
    }))
    
    ;; If there was a winner, refund them
    (match (get winner auction)
      winner (match (get winning-price auction)
        winning-price (try! (as-contract (stx-transfer? winning-price tx-sender winner)))
        false
      )
      true
    )
    
    (ok true)
  )
)
