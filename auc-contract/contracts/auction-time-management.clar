;; Auction Time Management Contract

;; Define data variables
(define-data-var auction-end-time uint u0)
(define-data-var auction-status (string-ascii 20) "active") ;; active, paused, ended, canceled
(define-data-var auction-creator principal tx-sender)
(define-data-var highest-bidder (optional principal) none)
(define-data-var highest-bid uint u0)
(define-data-var anti-snipe-window uint u300) ;; 5 minutes in seconds
(define-data-var extension-time uint u600) ;; 10 minutes in seconds

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-AUCTION-ENDED (err u101))
(define-constant ERR-AUCTION-PAUSED (err u102))
(define-constant ERR-AUCTION-CANCELED (err u103))
(define-constant ERR-INVALID-STATE (err u104))

;; Function to place a bid and check for anti-sniping
(define-public (place-bid (bid-amount uint))
  (let (
    (current-time stacks-block-height)
    (current-status (var-get auction-status))
  )
    ;; Check auction status - using separate if statements to return early on errors
    (if (is-eq current-status "ended") 
      (err (get error-code ERR-AUCTION-ENDED))
      (if (is-eq current-status "paused") 
        (err (get error-code ERR-AUCTION-PAUSED))
        (if (is-eq current-status "canceled") 
          (err (get error-code ERR-AUCTION-CANCELED))
          (if (not (is-eq current-status "active")) 
            (err (get error-code ERR-INVALID-STATE))
            
            ;; Continue with other checks only if status is active
            (if (>= current-time (var-get auction-end-time))
              (err (get error-code ERR-AUCTION-ENDED))
              (if (<= bid-amount (var-get highest-bid))
                (err u105)
                
                ;; All checks passed, update bid info
                (begin
                  ;; Update highest bid and bidder
                  (var-set highest-bid bid-amount)
                  (var-set highest-bidder (some tx-sender))
                  
                  ;; Check if bid is within anti-snipe window
                  (if (< (- (var-get auction-end-time) current-time) (var-get anti-snipe-window))
                    (begin
                      ;; Extend auction time
                      (var-set auction-end-time (+ (var-get auction-end-time) (var-get extension-time)))
                      (ok true)
                    )
                    (ok false)
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)

;; Function to extend auction manually
(define-public (extend-auction (extension uint))
  (begin
    ;; Only auction creator can extend
    (asserts! (is-eq tx-sender (var-get auction-creator)) ERR-NOT-AUTHORIZED)
    ;; Check auction is active
    (asserts! (is-eq (var-get auction-status) "active") ERR-INVALID-STATE)
    ;; Extend the auction
    (var-set auction-end-time (+ (var-get auction-end-time) extension))
    (ok true)))

;; Function to end auction
(define-public (end-auction)
  (let ((current-time (- stacks-block-height u1)))
    ;; Only creator or system (if time expired) can end auction
    (asserts! (or 
                (is-eq tx-sender (var-get auction-creator))
                (and 
                  (not (is-none current-time))
                  (>= (default-to u0 current-time) (var-get auction-end-time))))
              ERR-NOT-AUTHORIZED)
    ;; Check auction is active
    (asserts! (is-eq (var-get auction-status) "active") ERR-INVALID-STATE)
    ;; End the auction
    (var-set auction-status "ended")
    (ok (var-get highest-bidder))))

;; Function to pause auction
(define-public (pause-auction)
  (begin
    ;; Only auction creator can pause
    (asserts! (is-eq tx-sender (var-get auction-creator)) ERR-NOT-AUTHORIZED)
    ;; Check auction is active
    (asserts! (is-eq (var-get auction-status) "active") ERR-INVALID-STATE)
    ;; Pause the auction
    (var-set auction-status "paused")
    (ok true)))

;; Function to resume auction
(define-public (resume-auction)
  (begin
    ;; Only auction creator can resume
    (asserts! (is-eq tx-sender (var-get auction-creator)) ERR-NOT-AUTHORIZED)
    ;; Check auction is paused
    (asserts! (is-eq (var-get auction-status) "paused") ERR-INVALID-STATE)
    ;; Resume the auction
    (var-set auction-status "active")
    (ok true)))

;; Function to cancel auction
(define-public (cancel-auction)
  (begin
    ;; Only auction creator can cancel
    (asserts! (is-eq tx-sender (var-get auction-creator)) ERR-NOT-AUTHORIZED)
    ;; Check auction is not ended
    (asserts! (not (is-eq (var-get auction-status) "ended")) ERR-INVALID-STATE)
    ;; Cancel the auction
    (var-set auction-status "canceled")
    (ok true)))

;; Getter for auction status
(define-read-only (get-auction-status)
  (var-get auction-status))

;; Getter for auction end time
(define-read-only (get-auction-end-time)
  (var-get auction-end-time))

;; Getter for highest bid
(define-read-only (get-highest-bid)
  (var-get highest-bid))

;; Getter for highest bidder
(define-read-only (get-highest-bidder)
  (var-get highest-bidder))