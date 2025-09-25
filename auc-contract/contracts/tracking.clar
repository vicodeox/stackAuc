;; Auction Transparency and Data Tracking Smart Contract
;; Provides comprehensive auction data storage and retrieval functionality

;; Error codes
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-AUCTION-ACTIVE (err u400))
(define-constant ERR-AUCTION-ENDED (err u410))

;; Data structures
(define-map auctions
  { auction-id: uint }
  {
    item-name: (string-ascii 100),
    item-description: (string-ascii 500),
    seller: principal,
    start-time: uint,
    end-time: uint,
    starting-bid: uint,
    highest-bid: uint,
    highest-bidder: (optional principal),
    total-bids: uint,
    status: (string-ascii 20), ;; "active", "ended", "cancelled"
    created-at: uint
  }
)

(define-map bid-history
  { auction-id: uint, bid-index: uint }
  {
    bidder: principal,
    amount: uint,
    timestamp: uint,
    block-height: uint
  }
)

(define-map auction-winners
  { auction-id: uint }
  {
    winner: principal,
    winning-bid: uint,
    end-time: uint,
    total-bids: uint
  }
)

(define-map user-bid-count
  { user: principal, auction-id: uint }
  { bid-count: uint }
)

(define-map global-stats
  { stat-type: (string-ascii 50) }
  { value: uint }
)

;; Data variables
(define-data-var auction-counter uint u0)
(define-data-var total-auctions uint u0)
(define-data-var total-revenue uint u0)

;; Initialize global stats
(map-set global-stats { stat-type: "total-auctions" } { value: u0 })
(map-set global-stats { stat-type: "total-bids" } { value: u0 })
(map-set global-stats { stat-type: "total-revenue" } { value: u0 })

;; Get auction details
(define-read-only (get-auction-details (auction-id uint))
  (match (map-get? auctions { auction-id: auction-id })
    auction-data (ok auction-data)
    ERR-NOT-FOUND
  )
)

;; Get bid history for an auction
(define-read-only (get-bid-history (auction-id uint))
  (let ((auction-data (unwrap! (map-get? auctions { auction-id: auction-id }) ERR-NOT-FOUND)))
    (ok (map get-bid-by-index 
         (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19)))
  )
)

;; Helper function to get bid by index
(define-private (get-bid-by-index (bid-index uint))
  (map-get? bid-history { auction-id: u1, bid-index: bid-index })
)

;; ;; Get bid history with pagination
;; (define-read-only (get-bid-history-paginated (auction-id uint) (start-index uint) (limit uint))
;;   (let ((auction-data (unwrap! (map-get? auctions { auction-id: auction-id }) ERR-NOT-FOUND)))
;;     (ok (map (lambda (index) 
;;                (map-get? bid-history { auction-id: auction-id, bid-index: (+ start-index index) }))
;;              (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9)))
;;   )
;; )

;; Get auction winner
(define-read-only (get-winner (auction-id uint))
  (let ((auction-data (unwrap! (map-get? auctions { auction-id: auction-id }) ERR-NOT-FOUND)))
    (if (is-eq (get status auction-data) "ended")
      (match (map-get? auction-winners { auction-id: auction-id })
        winner-data (ok winner-data)
        ERR-NOT-FOUND)
      ERR-AUCTION-ACTIVE
    )
  )
)

;; Get auction history (all past auctions)
(define-read-only (get-auction-history (limit uint) (offset uint))
  (let ((total (var-get total-auctions)))
    (ok {
      total-auctions: total,
      auctions: (map get-auction-by-offset 
                     (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19))
    })
  )
)

;; Helper function to get auction by offset
(define-private (get-auction-by-offset (index uint))
  (map-get? auctions { auction-id: (+ index u1) })
)

;; Get user's auction history
(define-read-only (get-user-auction-history (user principal))
  (ok (filter is-user-auction 
              (map get-auction-by-offset 
                   (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19))))
)

;; Helper function to check if user participated in auction
(define-private (is-user-auction (auction-data (optional { item-name: (string-ascii 100), item-description: (string-ascii 500), seller: principal, start-time: uint, end-time: uint, starting-bid: uint, highest-bid: uint, highest-bidder: (optional principal), total-bids: uint, status: (string-ascii 20), created-at: uint })))
  (match auction-data
    auction (or (is-eq (get seller auction) tx-sender)
                (is-eq (get highest-bidder auction) (some tx-sender)))
    false)
)

;; Get comprehensive auction statistics
(define-read-only (get-auction-stats)
  (let (
    (total-auctions-stat (default-to u0 (get value (map-get? global-stats { stat-type: "total-auctions" }))))
    (total-bids-stat (default-to u0 (get value (map-get? global-stats { stat-type: "total-bids" }))))
    (total-revenue-stat (default-to u0 (get value (map-get? global-stats { stat-type: "total-revenue" }))))
  )
    (ok {
      total-auctions: total-auctions-stat,
      total-bids: total-bids-stat,
      total-revenue: total-revenue-stat,
      average-bid-size: (if (> total-bids-stat u0) (/ total-revenue-stat total-bids-stat) u0),
      average-revenue-per-auction: (if (> total-auctions-stat u0) (/ total-revenue-stat total-auctions-stat) u0)
    })
  )
)

;; Get auction performance metrics
(define-read-only (get-auction-performance (auction-id uint))
  (let ((auction-data (unwrap! (map-get? auctions { auction-id: auction-id }) ERR-NOT-FOUND)))
    (ok {
      auction-id: auction-id,
      total-bids: (get total-bids auction-data),
      starting-bid: (get starting-bid auction-data),
      highest-bid: (get highest-bid auction-data),
      bid-increase: (- (get highest-bid auction-data) (get starting-bid auction-data)),
      bid-increase-percentage: (if (> (get starting-bid auction-data) u0)
                                 (/ (* (- (get highest-bid auction-data) (get starting-bid auction-data)) u100)
                                    (get starting-bid auction-data))
                                 u0),
      duration: (- (get end-time auction-data) (get start-time auction-data)),
      status: (get status auction-data)
    })
  )
)

;; Get bidder statistics for an auction
(define-read-only (get-bidder-stats (auction-id uint))
  (let ((auction-data (unwrap! (map-get? auctions { auction-id: auction-id }) ERR-NOT-FOUND)))
    (ok {
      total-bidders: (get total-bids auction-data), ;; Simplified - in real implementation would count unique bidders
      highest-bidder: (get highest-bidder auction-data),
      total-bids: (get total-bids auction-data)
    })
  )
)

;; Get user's bidding statistics
(define-read-only (get-user-stats (user principal))
  (ok {
    total-bids-placed: (default-to u0 (get value (map-get? global-stats { stat-type: "user-total-bids" }))),
    auctions-won: u0, ;; Would need additional tracking
    auctions-participated: u0, ;; Would need additional tracking
    total-spent: u0 ;; Would need additional tracking
  })
)

;; Get recent auction activity
(define-read-only (get-recent-activity (limit uint))
  (let ((recent-auctions (var-get auction-counter)))
    (ok (map get-recent-auction-data 
             (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9)))
  )
)

;; Helper function for recent activity
(define-private (get-recent-auction-data (offset uint))
  (let ((auction-id (- (var-get auction-counter) offset)))
    (if (> auction-id u0)
      (map-get? auctions { auction-id: auction-id })
      none)
  )
)

;; Administrative function to create auction (for testing)
(define-public (create-auction (item-name (string-ascii 100)) 
                              (item-description (string-ascii 500))
                              (duration uint)
                              (starting-bid uint))
  (let ((auction-id (+ (var-get auction-counter) u1))
        (current-time stacks-block-height))
    (map-set auctions 
      { auction-id: auction-id }
      {
        item-name: item-name,
        item-description: item-description,
        seller: tx-sender,
        start-time: current-time,
        end-time: (+ current-time duration),
        starting-bid: starting-bid,
        highest-bid: starting-bid,
        highest-bidder: none,
        total-bids: u0,
        status: "active",
        created-at: current-time
      }
    )
    (var-set auction-counter auction-id)
    (var-set total-auctions (+ (var-get total-auctions) u1))
    (map-set global-stats { stat-type: "total-auctions" } { value: (+ (var-get total-auctions) u1) })
    (ok auction-id)
  )
)

;; Function to place bid (for testing and updating stats)
(define-public (place-bid (auction-id uint) (bid-amount uint))
  (let ((auction-data (unwrap! (map-get? auctions { auction-id: auction-id }) ERR-NOT-FOUND))
        (current-time stacks-block-height)
        (bid-index (get total-bids auction-data)))
    
    ;; Check if auction is active
    (asserts! (is-eq (get status auction-data) "active") ERR-AUCTION-ENDED)
    (asserts! (< current-time (get end-time auction-data)) ERR-AUCTION-ENDED)
    (asserts! (> bid-amount (get highest-bid auction-data)) (err u402))
    
    ;; Record the bid
    (map-set bid-history
      { auction-id: auction-id, bid-index: bid-index }
      {
        bidder: tx-sender,
        amount: bid-amount,
        timestamp: current-time,
        block-height: stacks-block-height
      }
    )
    
    ;; Update auction data
    (map-set auctions
      { auction-id: auction-id }
      (merge auction-data {
        highest-bid: bid-amount,
        highest-bidder: (some tx-sender),
        total-bids: (+ (get total-bids auction-data) u1)
      })
    )
    
    ;; Update global stats
    (let ((current-total-bids (default-to u0 (get value (map-get? global-stats { stat-type: "total-bids" }))))
          (current-revenue (default-to u0 (get value (map-get? global-stats { stat-type: "total-revenue" })))))
      (map-set global-stats { stat-type: "total-bids" } { value: (+ current-total-bids u1) })
      (map-set global-stats { stat-type: "total-revenue" } { value: (+ current-revenue bid-amount) })
    )
    
    (ok true)
  )
)

;; Function to end auction (for testing)
(define-public (end-auction (auction-id uint))
  (let ((auction-data (unwrap! (map-get? auctions { auction-id: auction-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq (get seller auction-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status auction-data) "active") ERR-AUCTION-ENDED)
    
    ;; Update auction status
    (map-set auctions
      { auction-id: auction-id }
      (merge auction-data { status: "ended" })
    )
    
    ;; Record winner if there were bids
    (match (get highest-bidder auction-data)
      winner (map-set auction-winners
               { auction-id: auction-id }
               {
                 winner: winner,
                 winning-bid: (get highest-bid auction-data),
                 end-time: stacks-block-height,
                 total-bids: (get total-bids auction-data)
               })
      true)
    
    (ok true)
  )
)
