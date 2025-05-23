;; Auction Payment and Fund Management Contract
;; Handles payments, escrow, and fund distribution for auction system

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_AUCTION_NOT_FOUND (err u101))
(define-constant ERR_AUCTION_ENDED (err u102))
(define-constant ERR_AUCTION_ACTIVE (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_INVALID_AMOUNT (err u105))
(define-constant ERR_INVALID_TOKEN (err u106))
(define-constant ERR_PAYMENT_FAILED (err u107))
(define-constant ERR_ALREADY_REFUNDED (err u108))
(define-constant ERR_NO_FUNDS_TO_WITHDRAW (err u109))
(define-constant ERR_INVALID_RECIPIENT (err u110))

;; Supported token types
(define-constant TOKEN_STX u1)
(define-constant TOKEN_USDC u2)
(define-constant TOKEN_DAI u3)
(define-constant TOKEN_PLATFORM u4)

;; Platform fee (2% = 200 basis points)
(define-constant PLATFORM_FEE_BPS u200)
(define-constant BASIS_POINTS u10000)

;; Data Variables
(define-data-var platform-fee-recipient principal CONTRACT_OWNER)
(define-data-var auction-counter uint u0)

;; Token contract addresses (mainnet addresses would be used in production)
(define-data-var usdc-contract principal 'SP3DX3H4FEYZJZ586MFBS25ZW3HZDMEW92260R2PR.Wrapped-USD)
(define-data-var dai-contract principal 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.wrapped-nothing)
(define-data-var platform-token-contract principal 'SP1H1733V5MZ3SZ9XRW9FKYGEZT0JDGEB8Y634C7R.miamicoin-token-v2)

;; Data Maps
(define-map auctions
  { auction-id: uint }
  {
    creator: principal,
    token-type: uint,
    reserve-price: uint,
    current-bid: uint,
    highest-bidder: (optional principal),
    end-time: uint,
    is-active: bool,
    funds-withdrawn: bool
  }
)

(define-map escrow-balances
  { auction-id: uint, bidder: principal }
  {
    amount: uint,
    token-type: uint,
    is-refunded: bool
  }
)

(define-map payment-splits
  { auction-id: uint }
  {
    recipients: (list 10 { recipient: principal, percentage: uint }),
    charity-recipient: (optional principal),
    charity-percentage: uint
  }
)

(define-map supported-tokens
  { token-type: uint }
  {
    contract-address: principal,
    is-active: bool,
    decimal-places: uint
  }
)

;; Initialize supported tokens
(map-set supported-tokens 
  { token-type: TOKEN_STX }
  { contract-address: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM, is-active: true, decimal-places: u6 }
)

;; Private Functions
(define-private (get-platform-fee (amount uint))
  (/ (* amount PLATFORM_FEE_BPS) BASIS_POINTS)
)

(define-private (validate-token-type (token-type uint))
  (match (map-get? supported-tokens { token-type: token-type })
    token-info (get is-active token-info)
    false
  )
)

(define-private (transfer-token (token-type uint) (amount uint) (sender principal) (recipient principal))
  (if (is-eq token-type TOKEN_STX)
    (stx-transfer? amount sender recipient)
    (let ((token-contract (unwrap! (get contract-address (map-get? supported-tokens { token-type: token-type })) ERR_INVALID_TOKEN)))
      ;; In a real implementation, you would call the appropriate SIP-010 transfer function
      ;; This is a simplified version
      (ok true)
    )
  )
)

;; Public Functions

;; Create auction with payment configuration
(define-public (create-auction 
  (token-type uint) 
  (reserve-price uint) 
  (duration uint)
  (payment-recipients (list 10 { recipient: principal, percentage: uint }))
  (charity-recipient (optional principal))
  (charity-percentage uint)
)
  (let (
    (auction-id (+ (var-get auction-counter) u1))
    (end-time (+ stacks-block-height duration))
  )
    (asserts! (validate-token-type token-type) ERR_INVALID_TOKEN)
    (asserts! (> reserve-price u0) ERR_INVALID_AMOUNT)
    (asserts! (> duration u0) ERR_INVALID_AMOUNT)
    
    ;; Validate payment split percentages sum to 100% or less
    (asserts! (<= (fold + (map get-percentage payment-recipients) charity-percentage) u10000) ERR_INVALID_AMOUNT)
    
    (map-set auctions
      { auction-id: auction-id }
      {
        creator: tx-sender,
        token-type: token-type,
        reserve-price: reserve-price,
        current-bid: u0,
        highest-bidder: none,
        end-time: end-time,
        is-active: true,
        funds-withdrawn: false
      }
    )
    
    (map-set payment-splits
      { auction-id: auction-id }
      {
        recipients: payment-recipients,
        charity-recipient: charity-recipient,
        charity-percentage: charity-percentage
      }
    )
    
    (var-set auction-counter auction-id)
    (ok auction-id)
  )
)

;; Handle payment for bids
(define-public (handle-payment (auction-id uint) (bid-amount uint))
  (let (
    (auction (unwrap! (map-get? auctions { auction-id: auction-id }) ERR_AUCTION_NOT_FOUND))
    (token-type (get token-type auction))
    (current-bid (get current-bid auction))
    (highest-bidder (get highest-bidder auction))
  )
    (asserts! (get is-active auction) ERR_AUCTION_ENDED)
    (asserts! (>= bid-amount (get reserve-price auction)) ERR_INSUFFICIENT_FUNDS)
    (asserts! (> bid-amount current-bid) ERR_INSUFFICIENT_FUNDS)
    (asserts! (<= stacks-block-height (get end-time auction)) ERR_AUCTION_ENDED)
    
    ;; Transfer funds to contract for escrow
    (try! (transfer-token token-type bid-amount tx-sender (as-contract tx-sender)))
    
    ;; Store escrow balance
    (map-set escrow-balances
      { auction-id: auction-id, bidder: tx-sender }
      {
        amount: bid-amount,
        token-type: token-type,
        is-refunded: false
      }
    )
    
    ;; Refund previous highest bidder if exists
    (match highest-bidder
      prev-bidder (try! (refund-bidder auction-id prev-bidder))
      true
    )
    
    ;; Update auction with new highest bid
    (map-set auctions
      { auction-id: auction-id }
      (merge auction {
        current-bid: bid-amount,
        highest-bidder: (some tx-sender)
      })
    )
    
    (ok true)
  )
)

;; Escrow funds (handled automatically in handle-payment)
(define-read-only (get-escrow-balance (auction-id uint) (bidder principal))
  (map-get? escrow-balances { auction-id: auction-id, bidder: bidder })
)


;; Refund escrow for outbid or canceled auctions
(define-public (refund-escrow (auction-id uint) (bidder principal))
  (let (
    (auction (unwrap! (map-get? auctions { auction-id: auction-id }) ERR_AUCTION_NOT_FOUND))
    (escrow-info (unwrap! (get-escrow-balance auction-id bidder) ERR_NO_FUNDS_TO_WITHDRAW))
  )
    (asserts! (not (get is-refunded escrow-info)) ERR_ALREADY_REFUNDED)
    (asserts! (not (is-eq (some bidder) (get highest-bidder auction))) ERR_UNAUTHORIZED)
    
    (try! (refund-bidder auction-id bidder))
    (ok true)
  )
)

;; Internal refund function
(define-private (refund-bidder (auction-id uint) (bidder principal))
  (let (
    (escrow-info (unwrap! (get-escrow-balance auction-id bidder) ERR_NO_FUNDS_TO_WITHDRAW))
  )
    (asserts! (not (get is-refunded escrow-info)) ERR_ALREADY_REFUNDED)
    
    ;; Transfer funds back to bidder
    (try! (as-contract (transfer-token 
      (get token-type escrow-info) 
      (get amount escrow-info) 
      tx-sender 
      bidder
    )))
    
    ;; Mark as refunded
    (map-set escrow-balances
      { auction-id: auction-id, bidder: bidder }
      (merge escrow-info { is-refunded: true })
    )
    
    (ok true)
  )
)

;; Helper function for payment distribution
(define-private (execute-single-payment 
  (recipient-info { recipient: principal, percentage: uint })
  (payment-data { amount: uint, token-type: uint, success: bool })
)
  (if (get success payment-data)
    (let (
      (payment-amount (/ (* (get amount payment-data) (get percentage recipient-info)) u10000))
    )
      (match (as-contract (transfer-token 
        (get token-type payment-data) 
        payment-amount 
        tx-sender 
        (get recipient recipient-info)
      ))
        success (merge payment-data { success: true })
        error (merge payment-data { success: false })
      )
    )
    payment-data
  )
)

;; Cancel auction (only by creator, refunds all bidders)
(define-public (cancel-auction (auction-id uint))
  (let (
    (auction (unwrap! (map-get? auctions { auction-id: auction-id }) ERR_AUCTION_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get creator auction)) ERR_UNAUTHORIZED)
    (asserts! (get is-active auction) ERR_AUCTION_ENDED)
    
    ;; Mark auction as inactive
    (map-set auctions
      { auction-id: auction-id }
      (merge auction { is-active: false })
    )
    
    ;; Refund highest bidder if exists
    (match (get highest-bidder auction)
      bidder (try! (refund-bidder auction-id bidder))
      true
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-auction (auction-id uint))
  (map-get? auctions { auction-id: auction-id })
)

(define-read-only (get-payment-split-config (auction-id uint))
  (map-get? payment-splits { auction-id: auction-id })
)

(define-read-only (is-token-supported (token-type uint))
  (validate-token-type token-type)
)

(define-read-only (get-platform-fee-for-amount (amount uint))
  (get-platform-fee amount)
)

;; Helper function to get percentage from recipient info
(define-private (get-percentage (recipient-info { recipient: principal, percentage: uint }))
  (get percentage recipient-info)
)