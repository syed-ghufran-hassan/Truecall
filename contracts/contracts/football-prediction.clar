;; Football Prediction Contract
;; A smart contract for football match predictions with access code control and leaderboard system

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-code (err u104))
(define-constant err-event-closed (err u105))
(define-constant err-event-not-closed (err u106))
(define-constant err-already-predicted (err u107))
(define-constant err-event-not-settled (err u108))
(define-constant err-event-already-settled (err u109))
(define-constant err-match-started (err u110))

;; Data Variables
(define-data-var event-nonce uint u0)
;; Add this for iteration
(define-data-var loop-index uint u0)

;; Outcome types: u1 = home win, u2 = draw, u3 = away win
(define-constant outcome-home u1)
(define-constant outcome-draw u2)
(define-constant outcome-away u3)

;; Points awarded for correct prediction
(define-constant points-per-correct-prediction u10)

;; Data Maps

;; Events storage
(define-map events
    { event-id: uint }
    {
        event-name: (string-ascii 100),
        creator: principal,
        access-code-hash: (buff 32),
        home-team: (string-ascii 50),
        away-team: (string-ascii 50),
        match-time: uint,
        oracle: principal,
        status: (string-ascii 10), ;; "open", "closed", "settled"
        final-result: (optional uint)
    }
)

;; Predictions storage - key is event-id + participant
(define-map predictions
    { event-id: uint, participant: principal }
    {
        event-name: (string-ascii 100),
        predicted-outcome: uint,
        timestamp: uint
    }
)

;; Leaderboard storage
(define-map leaderboard
    { participant: principal }
    {
        total-points: uint,
        correct-predictions: uint,
        total-predictions: uint
    }
)

;; Event participants list
(define-map event-participants
    { event-id: uint, participant: principal }
    { joined: bool }
)

;; Track participant count per event
(define-map event-participant-count
    { event-id: uint }
    { count: uint }
)

;; Store participants by index for retrieval
(define-map event-participant-by-index
    { event-id: uint, index: uint }
    { participant: principal }
)

;; Track events by creator
(define-map creator-event-count
    { creator: principal }
    { count: uint }
)

(define-map creator-event-by-index
    { creator: principal, index: uint }
    { event-id: uint }
)

;; Track events by status
(define-map status-event-count
    { status: (string-ascii 10) }
    { count: uint }
)

(define-map status-event-by-index
    { status: (string-ascii 10), index: uint }
    { event-id: uint }
)

;; Map event name to event ID for lookup
(define-map event-name-to-id
    { event-name: (string-ascii 100) }
    { event-id: uint }
)

;; =====================================================
;; READ-ONLY FUNCTIONS
;; =====================================================

;; Get event details
(define-read-only (get-event (event-id uint))
    (map-get? events { event-id: event-id })
)

;; Get prediction for a specific event and participant
(define-read-only (get-prediction (event-id uint) (participant principal))
    (map-get? predictions { event-id: event-id, participant: participant })
)

;; Get user statistics
(define-read-only (get-user-stats (participant principal))
    (default-to 
        { total-points: u0, correct-predictions: u0, total-predictions: u0 }
        (map-get? leaderboard { participant: participant })
    )
)

;; Check if user has joined an event
(define-read-only (has-joined-event (event-id uint) (participant principal))
    (is-some (map-get? event-participants { event-id: event-id, participant: participant }))
)

;; Get participant count for an event
(define-read-only (get-participant-count (event-id uint))
    (default-to u0 
        (get count (map-get? event-participant-count { event-id: event-id }))
    )
)

;; Get participant by index
(define-read-only (get-participant-at-index (event-id uint) (index uint))
    (get participant (map-get? event-participant-by-index { event-id: event-id, index: index }))
)

;; Get event count by creator
(define-read-only (get-creator-event-count (creator principal))
    (default-to u0 
        (get count (map-get? creator-event-count { creator: creator }))
    )
)

;; Get event ID by creator and index
(define-read-only (get-creator-event-at-index (creator principal) (index uint))
    (get event-id (map-get? creator-event-by-index { creator: creator, index: index }))
)

;; Get event count by status
(define-read-only (get-status-event-count (status (string-ascii 10)))
    (default-to u0 
        (get count (map-get? status-event-count { status: status }))
    )
)

;; Get event ID by status and index
(define-read-only (get-status-event-at-index (status (string-ascii 10)) (index uint))
    (get event-id (map-get? status-event-by-index { status: status, index: index }))
)

;; Check if event is within date range
(define-read-only (is-event-in-date-range (event-id uint) (start-time uint) (end-time uint))
    (match (get-event event-id)
        event
        (and (>= (get match-time event) start-time)
             (<= (get match-time event) end-time))
        false
    )
)

;; Get event ID by event name
(define-read-only (get-event-id-by-name (event-name (string-ascii 100)))
    (get event-id (map-get? event-name-to-id { event-name: event-name }))
)

;; Get event by name
(define-read-only (get-event-by-name (event-name (string-ascii 100)))
    (match (get-event-id-by-name event-name)
        event-id
        (get-event event-id)
        none
    )
)

;; =====================================================
;; PRIVATE FUNCTIONS
;; =====================================================

;; Private helper function to award points to a participant
(define-private (award-points-to-participant (event-id uint) (participant principal) (final-result uint))
    (let
        (
            (prediction (map-get? predictions { event-id: event-id, participant: participant }))
            (stats (get-user-stats participant))
        )
        (match prediction
            pred
            (if (is-eq (get predicted-outcome pred) final-result)
                ;; Award points for correct prediction
                (begin
                    (map-set leaderboard
                        { participant: participant }
                        {
                            total-points: (+ (get total-points stats) points-per-correct-prediction),
                            correct-predictions: (+ (get correct-predictions stats) u1),
                            total-predictions: (get total-predictions stats)
                        }
                    )
                    true
                )
                ;; No points for incorrect prediction
                true
            )
            ;; No prediction found, do nothing
            true
        )
    )
)

;; Process a single participant by index
(define-private (process-participant-at-index (event-id uint) (final-result uint) (index uint))
    (match (get-participant-at-index event-id index)
        participant
        (award-points-to-participant event-id participant final-result)
        true
    )
)

;; Process all participants using a simple iterative approach (no recursion)
(define-private (process-all-participants (event-id uint) (final-result uint) (total-count uint))
    (let
        (
            (index u0)
        )
        ;; Process each participant using a let binding and repeated calls
        (if (> total-count u0)
            (begin
                ;; Process participant 0
                (process-participant-at-index event-id final-result u0)
                (if (> total-count u1)
                    (begin
                        ;; Process participant 1
                        (process-participant-at-index event-id final-result u1)
                        (if (> total-count u2)
                            (begin
                                ;; Process participant 2
                                (process-participant-at-index event-id final-result u2)
                                (if (> total-count u3)
                                    (begin
                                        ;; Process participant 3
                                        (process-participant-at-index event-id final-result u3)
                                        (if (> total-count u4)
                                            (begin
                                                ;; Process participant 4
                                                (process-participant-at-index event-id final-result u4)
                                                (if (> total-count u5)
                                                    (begin
                                                        ;; Process participant 5
                                                        (process-participant-at-index event-id final-result u5)
                                                        (if (> total-count u6)
                                                            (begin
                                                                ;; Process participant 6
                                                                (process-participant-at-index event-id final-result u6)
                                                                (if (> total-count u7)
                                                                    (begin
                                                                        ;; Process participant 7
                                                                        (process-participant-at-index event-id final-result u7)
                                                                        (if (> total-count u8)
                                                                            (begin
                                                                                ;; Process participant 8
                                                                                (process-participant-at-index event-id final-result u8)
                                                                                (if (> total-count u9)
                                                                                    (begin
                                                                                        ;; Process participant 9
                                                                                        (process-participant-at-index event-id final-result u9)
                                                                                        true
                                                                                    )
                                                                                    true
                                                                                )
                                                                            )
                                                                            true
                                                                        )
                                                                    )
                                                                    true
                                                                )
                                                            )
                                                            true
                                                        )
                                                    )
                                                    true
                                                )
                                            )
                                            true
                                        )
                                    )
                                    true
                                )
                            )
                            true
                        )
                    )
                    true
                )
            )
            true
        )
    )
)

;; =====================================================
;; PUBLIC FUNCTIONS
;; =====================================================

;; Create a new event
(define-public (create-event 
    (event-name (string-ascii 100))
    (access-code (string-ascii 50))
    (home-team (string-ascii 50))
    (away-team (string-ascii 50))
    (match-time uint)
    (oracle principal)
)
    (let
        (
            (event-id (+ (var-get event-nonce) u1))
            (code-hash (sha256 (unwrap-panic (to-consensus-buff? access-code))))
            (creator-count (get-creator-event-count tx-sender))
            (status-count (get-status-event-count "open"))
        )
        ;; Update nonce
        (var-set event-nonce event-id)
        
        ;; Create event
        (map-set events
            { event-id: event-id }
            {
                event-name: event-name,
                creator: tx-sender,
                access-code-hash: code-hash,
                home-team: home-team,
                away-team: away-team,
                match-time: match-time,
                oracle: oracle,
                status: "open",
                final-result: none
            }
        )
        
        ;; Map event name to ID for lookup
        (map-set event-name-to-id
            { event-name: event-name }
            { event-id: event-id }
        )
        
        ;; Track event by creator
        (map-set creator-event-by-index
            { creator: tx-sender, index: creator-count }
            { event-id: event-id }
        )
        (map-set creator-event-count
            { creator: tx-sender }
            { count: (+ creator-count u1) }
        )
        
        ;; Track event by status
        (map-set status-event-by-index
            { status: "open", index: status-count }
            { event-id: event-id }
        )
        (map-set status-event-count
            { status: "open" }
            { count: (+ status-count u1) }
        )
        
        (ok event-id)
    )
)

;; Join event and place prediction
(define-public (join-event 
    (event-name (string-ascii 100))
    (access-code (string-ascii 50))
    (predicted-outcome uint)
)
    (let
        (
            (event-id (unwrap! (get-event-id-by-name event-name) err-not-found))
            (event (unwrap! (get-event event-id) err-not-found))
            (code-hash (sha256 (unwrap-panic (to-consensus-buff? access-code))))
        )
        ;; Verify access code
        (asserts! (is-eq code-hash (get access-code-hash event)) err-invalid-code)
        
        ;; Verify event is open
        (asserts! (is-eq (get status event) "open") err-event-closed)
        
        ;; Verify match hasn't started yet (using burn-block-height as proxy for time)
        (asserts! (< burn-block-height (get match-time event)) err-match-started)
        
        ;; Verify user hasn't already predicted
        (asserts! (is-none (get-prediction event-id tx-sender)) err-already-predicted)
        
        ;; Verify valid outcome
        (asserts! (or (is-eq predicted-outcome outcome-home)
                     (or (is-eq predicted-outcome outcome-draw)
                         (is-eq predicted-outcome outcome-away)))
                 err-unauthorized)
        
        ;; Record participation
        (let
            (
                (current-count (get-participant-count event-id))
            )
            (map-set event-participants
                { event-id: event-id, participant: tx-sender }
                { joined: true }
            )
            
            ;; Add participant to indexed list
            (map-set event-participant-by-index
                { event-id: event-id, index: current-count }
                { participant: tx-sender }
            )
            
            ;; Increment participant count
            (map-set event-participant-count
                { event-id: event-id }
                { count: (+ current-count u1) }
            )
        )
        
        ;; Store prediction
        (map-set predictions
            { event-id: event-id, participant: tx-sender }
            {
                event-name: (get event-name event),
                predicted-outcome: predicted-outcome,
                timestamp: stacks-block-height
            }
        )
        
        ;; Initialize leaderboard entry if new user
        (if (is-none (map-get? leaderboard { participant: tx-sender }))
            (map-set leaderboard
                { participant: tx-sender }
                { total-points: u0, correct-predictions: u0, total-predictions: u1 }
            )
            ;; Increment total predictions
            (let
                (
                    (stats (unwrap-panic (map-get? leaderboard { participant: tx-sender })))
                )
                (map-set leaderboard
                    { participant: tx-sender }
                    {
                        total-points: (get total-points stats),
                        correct-predictions: (get correct-predictions stats),
                        total-predictions: (+ (get total-predictions stats) u1)
                    }
                )
            )
        )
        
        (ok true)
    )
)

;; Close event (stop accepting predictions)
(define-public (close-event (event-id uint))
    (let
        (
            (event (unwrap! (get-event event-id) err-not-found))
            (closed-count (get-status-event-count "closed"))
        )
        ;; Only creator can close
        (asserts! (is-eq tx-sender (get creator event)) err-unauthorized)
        
        ;; Verify event is open
        (asserts! (is-eq (get status event) "open") err-event-closed)
        
        ;; Update status
        (map-set events
            { event-id: event-id }
            (merge event { status: "closed" })
        )
        
        ;; Track event in closed status
        (map-set status-event-by-index
            { status: "closed", index: closed-count }
            { event-id: event-id }
        )
        (map-set status-event-count
            { status: "closed" }
            { count: (+ closed-count u1) }
        )
        
        (ok true)
    )
)

;; Submit result (oracle only) and award points automatically
(define-public (submit-result (event-id uint) (final-result uint))
    (let
        (
            (event (unwrap! (get-event event-id) err-not-found))
            (participant-count (get-participant-count event-id))
            (settled-count (get-status-event-count "settled"))
        )
        ;; Only oracle can submit
        (asserts! (is-eq tx-sender (get oracle event)) err-unauthorized)
        
        ;; Verify event is closed
        (asserts! (is-eq (get status event) "closed") err-event-not-closed)
        
        ;; Verify valid outcome
        (asserts! (or (is-eq final-result outcome-home)
                     (or (is-eq final-result outcome-draw)
                         (is-eq final-result outcome-away)))
                 err-unauthorized)
        
        ;; Update event with result
        (map-set events
            { event-id: event-id }
            (merge event { 
                status: "settled",
                final-result: (some final-result)
            })
        )
        
        ;; Track event in settled status
        (map-set status-event-by-index
            { status: "settled", index: settled-count }
            { event-id: event-id }
        )
        (map-set status-event-count
            { status: "settled" }
            { count: (+ settled-count u1) }
        )
        
        ;; Automatically award points to all participants
        (process-all-participants event-id final-result participant-count)
        
        (ok true)
    )
)

;; Award points to a participant (called after result submission)
(define-public (award-points (event-id uint) (participant principal))
    (let
        (
            (event (unwrap! (get-event event-id) err-not-found))
            (prediction (unwrap! (get-prediction event-id participant) err-not-found))
            (final-result (unwrap! (get final-result event) err-event-not-settled))
            (stats (get-user-stats participant))
        )
        ;; Verify event is settled
        (asserts! (is-eq (get status event) "settled") err-event-not-settled)
        
        ;; Check if prediction was correct
        (if (is-eq (get predicted-outcome prediction) final-result)
            ;; Award points for correct prediction
            (begin
                (map-set leaderboard
                    { participant: participant }
                    {
                        total-points: (+ (get total-points stats) points-per-correct-prediction),
                        correct-predictions: (+ (get correct-predictions stats) u1),
                        total-predictions: (get total-predictions stats)
                    }
                )
                (ok { awarded: true, points: points-per-correct-prediction })
            )
            ;; No points for incorrect prediction
            (ok { awarded: false, points: u0 })
        )
    )
)

;; Update oracle address (creator only)
(define-public (update-oracle (event-id uint) (new-oracle principal))
    (let
        (
            (event (unwrap! (get-event event-id) err-not-found))
        )
        ;; Only creator can update
        (asserts! (is-eq tx-sender (get creator event)) err-unauthorized)
        
        ;; Cannot update after settlement
        (asserts! (not (is-eq (get status event) "settled")) err-event-already-settled)
        
        ;; Update oracle
        (map-set events
            { event-id: event-id }
            (merge event { oracle: new-oracle })
        )
        (ok true)
    )
)
