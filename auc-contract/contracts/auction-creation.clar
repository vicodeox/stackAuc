
;; title: auction-creation
;; version:
;; summary:
;; description:


;; title: auction-creation
;; version:
;; summary:
;; description:

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u100))
(define-constant err-auction-not-found (err u101))
(define-constant err-invalid-auction (err u102))
(define-constant err-auction-started (err u103))
(define-constant err-invalid-duration (err u104))
(define-constant err-invalid-price (err u105))
(define-constant err-house-not-found (err u106))

;; Data maps
(define-map auctions
  { auction-id: uint }
  {
    creator: principal,
    start-time: uint,
    duration: uint,
    starting-price: uint,
    reserve-price: (optional uint),
    item-id: (string-ascii 256),
    house-id: uint,
    status: (string-ascii 20)
  }
)

(define-map auction-houses
  { house-id: uint }
  {
    owner: principal,
    name: (string-ascii 64),
    fee-percentage: uint,
    min-auction-duration: uint,
    max-auction-duration: uint
  }
)

;; Variables
(define-data-var auction-nonce uint u0)
(define-data-var house-nonce uint u0)

;; Functions

;; Create a new auction house
(define-public (create-auction-house (name (string-ascii 64)) (fee-percentage uint) (min-duration uint) (max-duration uint))
  (let
    (
      (new-house-id (+ (var-get house-nonce) u1))
    )
    (asserts! (<= fee-percentage u100) err-invalid-price)
    (asserts! (< min-duration max-duration) err-invalid-duration)
    (map-set auction-houses
      { house-id: new-house-id }
      {
        owner: tx-sender,
        name: name,
        fee-percentage: fee-percentage,
        min-auction-duration: min-duration,
        max-auction-duration: max-duration
      }
    )
    (var-set house-nonce new-house-id)
    (ok new-house-id)
  )
)
;; Start a new auction
(define-public (start-auction (house-id uint) (duration uint) (starting-price uint) (reserve-price (optional uint)) (item-id (string-ascii 256)))
  (let
    (
      (new-auction-id (+ (var-get auction-nonce) u1))
      (house (unwrap! (map-get? auction-houses { house-id: house-id }) err-house-not-found))
    )
    (asserts! (and (>= duration (get min-auction-duration house)) (<= duration (get max-auction-duration house))) err-invalid-duration)
    (asserts! (> starting-price u0) err-invalid-price)
    (map-set auctions
      { auction-id: new-auction-id }
      {
        creator: tx-sender,
        start-time: stacks-block-height,
        duration: duration,
        starting-price: starting-price,
        reserve-price: reserve-price,
        item-id: item-id,
        house-id: house-id,
        status: "pending"
      }
    )
    (var-set auction-nonce new-auction-id)
    (ok new-auction-id)
  )
)

;; Set or modify the reserve price of an auction
(define-public (set-reserve-price (auction-id uint) (new-reserve-price uint))
  (let
    (
      (auction (unwrap! (map-get? auctions { auction-id: auction-id }) err-auction-not-found))
    )
    (asserts! (is-eq tx-sender (get creator auction)) err-not-authorized)
    (asserts! (is-eq (get status auction) "pending") err-auction-started)
    (asserts! (>= new-reserve-price (get starting-price auction)) err-invalid-price)
    (map-set auctions
      { auction-id: auction-id }
      (merge auction { reserve-price: (some new-reserve-price) })
    )
    (ok true)
  )
)

;; Modify auction details before any bids are placed
(define-public (modify-auction-details (auction-id uint) (new-duration (optional uint)) (new-starting-price (optional uint)))
  (let
    (
      (auction (unwrap! (map-get? auctions { auction-id: auction-id }) err-auction-not-found))
      (house (unwrap! (map-get? auction-houses { house-id: (get house-id auction) }) err-house-not-found))
    )
    (asserts! (is-eq tx-sender (get creator auction)) err-not-authorized)
    (asserts! (is-eq (get status auction) "pending") err-auction-started)
    
    (asserts! (match new-duration
                duration (and (>= duration (get min-auction-duration house))
                              (<= duration (get max-auction-duration house)))
                true)
              err-invalid-duration)
    
    (asserts! (match new-starting-price
                price (> price u0)
                true)
              err-invalid-price)
    
    (map-set auctions
      { auction-id: auction-id }
      (merge auction 
        {
          duration: (default-to (get duration auction) new-duration),
          starting-price: (default-to (get starting-price auction) new-starting-price)
        }
      )
    )
    (ok true)
  )
)

;; Read-only functions

;; Get auction details
(define-read-only (get-auction (auction-id uint))
  (map-get? auctions { auction-id: auction-id })
)

;; Get auction house details
(define-read-only (get-auction-house (house-id uint))
  (map-get? auction-houses { house-id: house-id })
)
