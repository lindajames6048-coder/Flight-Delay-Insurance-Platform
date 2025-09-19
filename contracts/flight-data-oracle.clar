;; Flight Data Oracle Contract
;; Integration with FlightAware and airline APIs for delay verification
;; Provides trusted data source for payout decisions and handles data authentication

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_FLIGHT (err u101))
(define-constant ERR_DATA_NOT_FOUND (err u102))
(define-constant ERR_INVALID_TIMESTAMP (err u103))
(define-constant ERR_ORACLE_OFFLINE (err u104))
(define-constant MIN_DELAY_THRESHOLD u15)
(define-constant MAX_DELAY_THRESHOLD u480)

;; Data maps and variables
(define-map flight-data
    {
        flight-number: (string-ascii 10),
        flight-date: uint
    }
    {
        departure-time: uint,
        arrival-time: uint,
        scheduled-departure: uint,
        scheduled-arrival: uint,
        delay-minutes: uint,
        status: (string-ascii 20),
        last-updated: uint,
        verified: bool
    }
)

(define-map authorized-oracles principal bool)
(define-map airline-apis
    (string-ascii 10)
    {
        api-endpoint: (string-ascii 100),
        api-key-hash: (buff 32),
        active: bool
    }
)

(define-data-var oracle-status bool true)
(define-data-var update-fee uint u1000)
(define-data-var verification-threshold uint u2)
(define-data-var total-updates uint u0)

;; Private functions
(define-private (is-authorized-oracle (oracle principal))
    (default-to false (map-get? authorized-oracles oracle))
)

(define-private (calculate-delay
    (scheduled uint)
    (actual uint)
    )
    (if (> actual scheduled)
        (/ (- actual scheduled) u60)
        u0
    )
)

(define-private (is-valid-flight-number (flight-num (string-ascii 10)))
    (and
        (> (len flight-num) u0)
        (<= (len flight-num) u10)
    )
)

(define-private (is-valid-timestamp (timestamp uint))
    (and
        (> timestamp u0)
        (<= timestamp (+ stacks-block-height u144000))
    )
)

(define-private (update-flight-status
    (flight-number (string-ascii 10))
    (flight-date uint)
    (departure uint)
    (arrival uint)
    (scheduled-dep uint)
    (scheduled-arr uint)
    )
    (let
        (
            (delay-dep (calculate-delay scheduled-dep departure))
            (delay-arr (calculate-delay scheduled-arr arrival))
            (max-delay (if (> delay-dep delay-arr) delay-dep delay-arr))
            (flight-status (if (> max-delay u0) "DELAYED" "ON_TIME"))
        )
        (map-set flight-data
            {flight-number: flight-number, flight-date: flight-date}
            {
                departure-time: departure,
                arrival-time: arrival,
                scheduled-departure: scheduled-dep,
                scheduled-arrival: scheduled-arr,
                delay-minutes: max-delay,
                status: flight-status,
                last-updated: stacks-block-height,
                verified: true
            }
        )
    )
)

;; Public functions
(define-public (add-authorized-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set authorized-oracles oracle true)
        (ok true)
    )
)

(define-public (remove-authorized-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-delete authorized-oracles oracle)
        (ok true)
    )
)

(define-public (register-airline-api
    (airline-code (string-ascii 10))
    (endpoint (string-ascii 100))
    (api-key-hash (buff 32))
    )
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set airline-apis airline-code
            {
                api-endpoint: endpoint,
                api-key-hash: api-key-hash,
                active: true
            }
        )
        (ok true)
    )
)

(define-public (update-flight-data
    (flight-number (string-ascii 10))
    (flight-date uint)
    (departure-time uint)
    (arrival-time uint)
    (scheduled-departure uint)
    (scheduled-arrival uint)
    )
    (begin
        (asserts! (is-authorized-oracle tx-sender) ERR_UNAUTHORIZED)
        (asserts! (var-get oracle-status) ERR_ORACLE_OFFLINE)
        (asserts! (is-valid-flight-number flight-number) ERR_INVALID_FLIGHT)
        (asserts! (is-valid-timestamp flight-date) ERR_INVALID_TIMESTAMP)
        (asserts! (is-valid-timestamp departure-time) ERR_INVALID_TIMESTAMP)
        
        (update-flight-status
            flight-number
            flight-date
            departure-time
            arrival-time
            scheduled-departure
            scheduled-arrival
        )
        
        (var-set total-updates (+ (var-get total-updates) u1))
        (ok true)
    )
)

(define-public (verify-flight-delay
    (flight-number (string-ascii 10))
    (flight-date uint)
    )
    (let
        (
            (flight-info (map-get? flight-data
                {flight-number: flight-number, flight-date: flight-date}
            ))
        )
        (match flight-info
            data (ok {
                delay-minutes: (get delay-minutes data),
                status: (get status data),
                verified: (get verified data),
                last-updated: (get last-updated data)
            })
            ERR_DATA_NOT_FOUND
        )
    )
)

(define-public (set-oracle-status (status bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set oracle-status status)
        (ok true)
    )
)

(define-public (set-update-fee (fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set update-fee fee)
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-flight-info
    (flight-number (string-ascii 10))
    (flight-date uint)
    )
    (map-get? flight-data {flight-number: flight-number, flight-date: flight-date})
)

(define-read-only (is-flight-delayed
    (flight-number (string-ascii 10))
    (flight-date uint)
    (threshold uint)
    )
    (let
        (
            (flight-info (map-get? flight-data
                {flight-number: flight-number, flight-date: flight-date}
            ))
        )
        (match flight-info
            data (>= (get delay-minutes data) threshold)
            false
        )
    )
)

(define-read-only (get-oracle-status)
    (var-get oracle-status)
)

(define-read-only (get-total-updates)
    (var-get total-updates)
)

(define-read-only (get-update-fee)
    (var-get update-fee)
)
