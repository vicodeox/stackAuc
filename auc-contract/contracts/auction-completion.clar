;; Auction Completion and Winner Transfer Contract
;; Handles auction finalization, ownership transfer, and reward distribution

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-AUCTION-NOT-FOUND (err u101))
(define-constant ERR-AUCTION-NOT-ENDED (err u102))
(define-constant ERR-AUCTION-ALREADY-FINALIZED (err u103))
(define-constant ERR-INVALID-WINNER (err u104))
(define-constant ERR-TRANSFER-FAILED (err u105))
(define-constant ERR-INSUFFICIENT-BALANCE (err u106))
(define-constant ERR-INVALID-REFERRAL (err u107))

;; Data Variables
(define-data-var loyalty-reward-rate uint u10) ;; 10 points per STX bid
(define-data-var referral-reward-rate uint u5) ;; 5% of bid amount
(define-data-var platform-fee-rate uint u250) ;; 2.5% platform fee

;; Data Maps
(define-map auctions
  { auction-id: uint }
  {
    creator: principal,
    item-id: uint,
    highest-bidder: (optional principal),
    highest-bid: uint,
    end-block: uint,
    finalized: bool,
    item-transferred: bool
  }
)

(define-map auction-items
  { item-id: uint }
  {
    owner: principal,
    metadata-uri: (string-ascii 256),
    item-type: (string-ascii 50)
  }
)

(define-map user-loyalty-points
  { user: principal }
  { points: uint }
)

(define-map user-referrals
  { referrer: principal }
  { total-referrals: uint, total-rewards: uint }
)

(define-map bid-history
  { auction-id: uint, bidder: principal }
  { bid-amount: uint, stacks-block-height: uint }
)

;; Read-only functions
(define-read-only (get-auction (auction-id uint))
  (map-get? auctions { auction-id: auction-id })
)

(define-read-only (get-auction-item (item-id uint))
  (map-get? auction-items { item-id: item-id })
)

(define-read-only (get-loyalty-points (user principal))
  (default-to u0 (get points (map-get? user-loyalty-points { user: user })))
)

(define-read-only (get-referral-stats (referrer principal))
  (map-get? user-referrals { referrer: referrer })
)

(define-read-only (is-auction-ended (auction-id uint))
  (match (get-auction auction-id)
    auction-data (>= stacks-block-height (get end-block auction-data))
    false
  )
)

(define-read-only (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u10000)
)

;; Private functions
(define-private (update-loyalty-points (user principal) (bid-amount uint))
  (let ((current-points (get-loyalty-points user))
        (new-points (+ current-points (* bid-amount (var-get loyalty-reward-rate)))))
    (map-set user-loyalty-points
      { user: user }
      { points: new-points }
    )
  )
)

(define-private (process-referral-reward (referrer principal) (bid-amount uint))
  (let ((reward-amount (/ (* bid-amount (var-get referral-reward-rate)) u100))
        (current-stats (default-to { total-referrals: u0, total-rewards: u0 }
                                  (get-referral-stats referrer))))
    (map-set user-referrals
      { referrer: referrer }
      {
        total-referrals: (+ (get total-referrals current-stats) u1),
        total-rewards: (+ (get total-rewards current-stats) reward-amount)
      }
    )
    (stx-transfer? reward-amount tx-sender referrer)
  )
)

;; Public functions

;; Transfer ownership of auction item to winner
(define-public (transfer-ownership (auction-id uint))
  (let ((auction-data (unwrap! (get-auction auction-id) ERR-AUCTION-NOT-FOUND)))
    (asserts! (is-auction-ended auction-id) ERR-AUCTION-NOT-ENDED)
    (asserts! (not (get item-transferred auction-data)) ERR-AUCTION-ALREADY-FINALIZED)
    
    (match (get highest-bidder auction-data)
      winner (let ((item-data (unwrap! (get-auction-item (get item-id auction-data)) ERR-AUCTION-NOT-FOUND)))
               ;; Update item ownership
               (map-set auction-items
                 { item-id: (get item-id auction-data) }
                 (merge item-data { owner: winner })
               )
               ;; Mark item as transferred
               (map-set auctions
                 { auction-id: auction-id }
                 (merge auction-data { item-transferred: true })
               )
               (ok true))
      ERR-INVALID-WINNER
    )
  )
)

;; Finalize auction and distribute funds
(define-public (finalize-auction (auction-id uint))
  (let ((auction-data (unwrap! (get-auction auction-id) ERR-AUCTION-NOT-FOUND)))
    (asserts! (is-auction-ended auction-id) ERR-AUCTION-NOT-ENDED)
    (asserts! (not (get finalized auction-data)) ERR-AUCTION-ALREADY-FINALIZED)
    
    (match (get highest-bidder auction-data)
      winner (let ((bid-amount (get highest-bid auction-data))
                   (platform-fee (calculate-platform-fee bid-amount))
                   (creator-amount (- bid-amount platform-fee)))
               ;; Transfer funds to auction creator
               (try! (stx-transfer? creator-amount tx-sender (get creator auction-data)))
               ;; Transfer platform fee
               (try! (stx-transfer? platform-fee tx-sender CONTRACT-OWNER))
               ;; Transfer item ownership
               (try! (transfer-ownership auction-id))
               ;; Mark auction as finalized
               (map-set auctions
                 { auction-id: auction-id }
                 (merge auction-data { finalized: true })
               )
               (ok true))
      ;; No winner, return item to creator
      (begin
        (map-set auctions
          { auction-id: auction-id }
          (merge auction-data { finalized: true })
        )
        (ok true))
    )
  )
)

;; Reward bidder with loyalty points
(define-public (reward-bidder (auction-id uint) (bidder principal) (bid-amount uint))
  (begin
    (asserts! (is-some (get-auction auction-id)) ERR-AUCTION-NOT-FOUND)
    ;; Record bid history
    (map-set bid-history
      { auction-id: auction-id, bidder: bidder }
      { bid-amount: bid-amount, stacks-block-height: stacks-block-height }
    )
    ;; Update loyalty points
    (update-loyalty-points bidder bid-amount)
    (ok true)
  )
)

;; Reward loyalty for repeat bidders
(define-public (reward-loyalty (user principal) (bonus-points uint))
  (begin
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender user)) ERR-NOT-AUTHORIZED)
    (let ((current-points (get-loyalty-points user)))
      (map-set user-loyalty-points
        { user: user }
        { points: (+ current-points bonus-points) }
      )
    )
    (ok true)
  )
)

;; Reward bidder referral
(define-public (reward-bidder-referral (referrer principal) (new-bidder principal) (bid-amount uint))
  (begin
    (asserts! (not (is-eq referrer new-bidder)) ERR-INVALID-REFERRAL)
    ;; Process referral reward
    (try! (process-referral-reward referrer bid-amount))
    ;; Give bonus loyalty points to new bidder
    (update-loyalty-points new-bidder (* bid-amount u2)) ;; Double points for referred users
    (ok true)
  )
)

;; Redeem loyalty points for STX
(define-public (redeem-loyalty-points (points-to-redeem uint))
  (let ((current-points (get-loyalty-points tx-sender))
        (stx-amount (/ points-to-redeem u100))) ;; 100 points = 1 STX
    (asserts! (>= current-points points-to-redeem) ERR-INSUFFICIENT-BALANCE)
    ;; Deduct points
    (map-set user-loyalty-points
      { user: tx-sender }
      { points: (- current-points points-to-redeem) }
    )
    ;; Transfer STX
    (stx-transfer? stx-amount CONTRACT-OWNER tx-sender)
  )
)

;; Admin functions
(define-public (set-loyalty-reward-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set loyalty-reward-rate new-rate)
    (ok true)
  )
)

(define-public (set-referral-reward-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-rate u100) (err u108)) ;; Max 100%
    (var-set referral-reward-rate new-rate)
    (ok true)
  )
)

(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-rate u1000) (err u109)) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

;; Create auction item (for testing)
(define-public (create-auction-item (item-id uint) (metadata-uri (string-ascii 256)) (item-type (string-ascii 50)))
  (begin
    (map-set auction-items
      { item-id: item-id }
      {
        owner: tx-sender,
        metadata-uri: metadata-uri,
        item-type: item-type
      }
    )
    (ok true)
  )
)

;; Create auction (for testing)
(define-public (create-auction (auction-id uint) (item-id uint) (duration uint))
  (let ((item-data (unwrap! (get-auction-item item-id) ERR-AUCTION-NOT-FOUND)))
    (asserts! (is-eq (get owner item-data) tx-sender) ERR-NOT-AUTHORIZED)
    (map-set auctions
      { auction-id: auction-id }
      {
        creator: tx-sender,
        item-id: item-id,
        highest-bidder: none,
        highest-bid: u0,
        end-block: (+ stacks-block-height duration),
        finalized: false,
        item-transferred: false
      }
    )
    (ok true)
  )
)

;; Place bid (for testing)
(define-public (place-bid (auction-id uint) (bid-amount uint))
  (let ((auction-data (unwrap! (get-auction auction-id) ERR-AUCTION-NOT-FOUND)))
    (asserts! (not (is-auction-ended auction-id)) ERR-AUCTION-NOT-ENDED)
    (asserts! (> bid-amount (get highest-bid auction-data)) (err u110))
    
    ;; Return previous highest bid if exists
    (match (get highest-bidder auction-data)
      previous-bidder (try! (stx-transfer? (get highest-bid auction-data) tx-sender previous-bidder))
      true
    )
    
    ;; Transfer new bid amount
    (try! (stx-transfer? bid-amount tx-sender (as-contract tx-sender)))
    
    ;; Update auction
    (map-set auctions
      { auction-id: auction-id }
      (merge auction-data {
        highest-bidder: (some tx-sender),
        highest-bid: bid-amount
      })
    )
    
    ;; Reward bidder with loyalty points
    (try! (reward-bidder auction-id tx-sender bid-amount))
    
    (ok true)
  )
)
