
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
