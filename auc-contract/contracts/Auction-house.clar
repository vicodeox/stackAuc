
;; title: Auction-house
;; version:
;; summary:
;; description:

;; Auction House Smart Contract
;; Supports creating and managing auctions with flexible features

(define-constant ERR-NOT-OWNER (err u1))
(define-constant ERR-AUCTION-EXISTS (err u2))
(define-constant ERR-AUCTION-NOT-FOUND (err u3))
(define-constant ERR-INVALID-PARAMS (err u4))
(define-constant ERR-BID-PLACED (err u5))

;; Auction House Data Structures
(define-map auction-houses 
  {house-id: uint} 
  {
    owner: principal,
    name: (string-utf8 50),
    fee-percentage: uint
  }
)

(define-map auctions 
  {auction-id: uint} 
  {
    house-id: uint,
    seller: principal,
    item-identifier: (string-utf8 256),
    start-price: uint,
    reserve-price: (optional uint),
    start-time: uint,
    duration: uint,
    highest-bidder: (optional principal),
    highest-bid: (optional uint),
    is-active: bool
  }
)

;; Auction House Tracking
(define-data-var next-auction-house-id uint u0)
(define-data-var next-auction-id uint u0)

;; Create an Auction House
(define-public (create-auction-house 
  (name (string-utf8 50)) 
  (fee-percentage uint)
)
  (let 
    (
      (house-id (var-get next-auction-house-id))
      (new-house-id (+ house-id u1))
    )
    ;; Validate fee percentage (max 10%)
    (asserts! (< fee-percentage u11) (err ERR-INVALID-PARAMS))
    
    ;; Create auction house entry
    (map-set auction-houses 
      {house-id: house-id} 
      {
        owner: tx-sender,
        name: name,
        fee-percentage: fee-percentage
      }
    )
    
    ;; Update next house ID
    (var-set next-auction-house-id new-house-id)
    
    ;; Return the created house ID
    (ok house-id)
)
)

;; Start a new auction
(define-public (start-auction 
  (house-id uint)
  (item-identifier (string-utf8 256))
  (start-price uint)
  (reserve-price (optional uint))
  (duration uint)
)
  (let 
    (
      (auction-id (var-get next-auction-id))
      (new-auction-id (+ auction-id u1))
    )
    ;; Validate auction parameters
    (asserts! (> duration u0) (err ERR-INVALID-PARAMS))
    (asserts! (is-some (map-get? auction-houses {house-id: house-id})) 
      (err ERR-AUCTION-NOT-FOUND)
    )
    
    ;; Optional reserve price check
    (match reserve-price 
      price (asserts! (>= price start-price) (err ERR-INVALID-PARAMS))
      true
    )
    
    ;; Create auction entry
    (map-set auctions 
      {auction-id: auction-id} 
      {
        house-id: house-id,
        seller: tx-sender,
        item-identifier: item-identifier,
        start-price: start-price,
        reserve-price: reserve-price,
        start-time: stacks-block-height,
        duration: duration,
        highest-bidder: none,
        highest-bid: none,
        is-active: true
      }
    )
    
    ;; Update next auction ID
    (var-set next-auction-id new-auction-id)
    
    ;; Return the created auction ID
    (ok auction-id)
)
)

;; Set or modify reserve price (before any bids)
(define-public (set-reserve-price 
  (auction-id uint)
  (new-reserve-price uint)
)
  (let 
    (
      (auction (unwrap! 
        (map-get? auctions {auction-id: auction-id}) 
        (err ERR-AUCTION-NOT-FOUND)
      ))
    )
    ;; Ensure only seller can modify
    (asserts! (is-eq tx-sender (get seller auction)) (err ERR-NOT-OWNER))
    
    ;; Ensure no bids have been placed
    (asserts! (is-none (get highest-bidder auction)) (err ERR-BID-PLACED))
    
    ;; Ensure new reserve is at least start price
    (asserts! (>= new-reserve-price (get start-price auction)) 
      (err ERR-INVALID-PARAMS)
    )
    
    ;; Update reserve price
    (map-set auctions 
      {auction-id: auction-id}
      (merge auction {reserve-price: (some new-reserve-price)})
    )
    
    (ok true)
))

;; Modify auction details before any bids
(define-public (modify-auction-details 
  (auction-id uint)
  (new-start-price (optional uint))
  (new-duration (optional uint))
)
  (let 
    (
      (auction (unwrap! 
        (map-get? auctions {auction-id: auction-id}) 
        (err ERR-AUCTION-NOT-FOUND)
      ))
    )
    ;; Ensure only seller can modify
    (asserts! (is-eq tx-sender (get seller auction)) (err ERR-NOT-OWNER))
    
    ;; Ensure no bids have been placed
    (asserts! (is-none (get highest-bidder auction)) (err ERR-BID-PLACED))
    
    ;; Optional start price update
    (let 
      (
        (updated-auction 
          (match new-start-price 
            price (merge auction {start-price: price})
            auction
          )
        )
        (final-auction 
          (match new-duration 
            duration (merge updated-auction {duration: duration})
            updated-auction
          )
        )
      )
      
      ;; Update auction details
      (map-set auctions 
        {auction-id: auction-id}
        final-auction
      )
      
      (ok true)
    )
))

;; Read-only function to get auction details
(define-read-only (get-auction-details (auction-id uint))
  (map-get? auctions {auction-id: auction-id})
)

;; Read-only function to get auction house details
(define-read-only (get-auction-house-details (house-id uint))
  (map-get? auction-houses {house-id: house-id})
)