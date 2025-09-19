;; Premium Calculator Contract
;; Dynamic pricing based on route history and seasonal patterns
;; Analyzes historical flight data and calculates insurance premiums

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_INVALID_ROUTE (err u301))
(define-constant ERR_INVALID_DATE (err u302))
(define-constant ERR_INSUFFICIENT_DATA (err u303))
(define-constant ERR_INVALID_PARAMETERS (err u304))
(define-constant BASE_PREMIUM u10000)
(define-constant MAX_PREMIUM_MULTIPLIER u500)
(define-constant MIN_PREMIUM_MULTIPLIER u50)
(define-constant SEASONAL_ADJUSTMENT_MAX u200)
(define-constant ROUTE_RISK_MULTIPLIER u150)

;; Data maps and variables
(define-map route-statistics
    {
        origin: (string-ascii 5),
        destination: (string-ascii 5)
    }
    {
        total-flights: uint,
        delayed-flights: uint,
        average-delay: uint,
        last-updated: uint,
        risk-score: uint
    }
)

(define-map airline-performance
    (string-ascii 10)
    {
        total-flights: uint,
        on-time-rate: uint,
        average-delay: uint,
        reliability-score: uint,
        premium-modifier: uint
    }
)

(define-map seasonal-factors
    uint
    {
        month: uint,
        weather-risk: uint,
        holiday-factor: uint,
        demand-multiplier: uint
    }
)

(define-map historical-premiums
    {
        route-hash: (buff 32),
        date: uint
    }
    {
        base-premium: uint,
        final-premium: uint,
        risk-factors: uint,
        seasonal-adjustment: uint
    }
)

(define-data-var base-premium-rate uint BASE_PREMIUM)
(define-data-var risk-tolerance uint u100)
(define-data-var seasonal-weight uint u25)
(define-data-var airline-weight uint u30)
(define-data-var route-weight uint u45)
(define-data-var total-calculations uint u0)

;; Private functions
(define-private (calculate-delay-percentage (delayed uint) (total uint))
    (if (> total u0)
        (/ (* delayed u10000) total)
        u0
    )
)

(define-private (calculate-risk-score (delay-percentage uint) (avg-delay uint))
    (let
        (
            (delay-factor (/ delay-percentage u100))
            (duration-factor (/ avg-delay u10))
        )
        (+ delay-factor duration-factor)
    )
)

(define-private (get-seasonal-multiplier (month uint))
    (let
        (
            (seasonal-data (map-get? seasonal-factors month))
        )
        (match seasonal-data
            data (+ u100 (+ (get weather-risk data) (get holiday-factor data)))
            u100
        )
    )
)

(define-private (get-airline-modifier (airline (string-ascii 10)))
    (let
        (
            (airline-data (map-get? airline-performance airline))
        )
        (match airline-data
            data (get premium-modifier data)
            u100
        )
    )
)

(define-private (calculate-route-premium
    (origin (string-ascii 5))
    (destination (string-ascii 5))
    )
    (let
        (
            (route-data (map-get? route-statistics
                {origin: origin, destination: destination}))
        )
        (match route-data
            data (let
                (
                    (delay-rate (calculate-delay-percentage
                        (get delayed-flights data)
                        (get total-flights data)))
                    (risk-premium (/ (* (var-get base-premium-rate) delay-rate) u10000))
                )
                (+ (var-get base-premium-rate) risk-premium)
            )
            (var-get base-premium-rate)
        )
    )
)

(define-private (apply-seasonal-adjustment (base-premium uint) (month uint))
    (let
        (
            (seasonal-multiplier (get-seasonal-multiplier month))
            (adjustment (/ (* base-premium seasonal-multiplier) u100))
        )
        adjustment
    )
)

(define-private (create-route-hash (origin (string-ascii 5)) (destination (string-ascii 5)))
    (sha256 (unwrap-panic (to-consensus-buff? (concat (concat origin "-") destination))))
)

(define-private (is-valid-airport-code (code (string-ascii 5)))
    (and
        (is-eq (len code) u3)
        (> (len code) u0)
    )
)

(define-private (is-valid-month (month uint))
    (and (>= month u1) (<= month u12))
)

;; Public functions
(define-public (update-route-statistics
    (origin (string-ascii 5))
    (destination (string-ascii 5))
    (total-flights uint)
    (delayed-flights uint)
    (avg-delay uint)
    )
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (is-valid-airport-code origin) ERR_INVALID_ROUTE)
        (asserts! (is-valid-airport-code destination) ERR_INVALID_ROUTE)
        (asserts! (>= total-flights delayed-flights) ERR_INVALID_PARAMETERS)
        
        (let
            (
                (delay-percentage (calculate-delay-percentage delayed-flights total-flights))
                (risk-score (calculate-risk-score delay-percentage avg-delay))
            )
            (map-set route-statistics
                {origin: origin, destination: destination}
                {
                    total-flights: total-flights,
                    delayed-flights: delayed-flights,
                    average-delay: avg-delay,
                    last-updated: stacks-block-height,
                    risk-score: risk-score
                }
            )
        )
        (ok true)
    )
)

(define-public (update-airline-performance
    (airline (string-ascii 10))
    (total-flights uint)
    (on-time-rate uint)
    (avg-delay uint)
    )
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= on-time-rate u10000) ERR_INVALID_PARAMETERS)
        
        (let
            (
                (reliability (/ on-time-rate u100))
                (modifier (if (> on-time-rate u8000) u90
                            (if (> on-time-rate u6000) u100 u120)))
            )
            (map-set airline-performance airline
                {
                    total-flights: total-flights,
                    on-time-rate: on-time-rate,
                    average-delay: avg-delay,
                    reliability-score: reliability,
                    premium-modifier: modifier
                }
            )
        )
        (ok true)
    )
)

(define-public (set-seasonal-factors
    (month uint)
    (weather-risk uint)
    (holiday-factor uint)
    (demand-multiplier uint)
    )
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (is-valid-month month) ERR_INVALID_DATE)
        (asserts! (<= weather-risk u100) ERR_INVALID_PARAMETERS)
        (asserts! (<= holiday-factor u100) ERR_INVALID_PARAMETERS)
        
        (map-set seasonal-factors month
            {
                month: month,
                weather-risk: weather-risk,
                holiday-factor: holiday-factor,
                demand-multiplier: demand-multiplier
            }
        )
        (ok true)
    )
)

(define-public (calculate-flight-premium
    (origin (string-ascii 5))
    (destination (string-ascii 5))
    (airline (string-ascii 10))
    (flight-date uint)
    (coverage-amount uint)
    )
    (let
        (
            (month (mod flight-date u12))
            (route-premium (calculate-route-premium origin destination))
            (seasonal-premium (apply-seasonal-adjustment route-premium (+ month u1)))
            (airline-modifier (get-airline-modifier airline))
            (final-premium (/ (* seasonal-premium airline-modifier) u100))
            (coverage-adjusted (/ (* final-premium coverage-amount) u100000))
            (route-hash (create-route-hash origin destination))
        )
        (asserts! (is-valid-airport-code origin) ERR_INVALID_ROUTE)
        (asserts! (is-valid-airport-code destination) ERR_INVALID_ROUTE)
        (asserts! (> coverage-amount u0) ERR_INVALID_PARAMETERS)
        
        (map-set historical-premiums
            {route-hash: route-hash, date: flight-date}
            {
                base-premium: route-premium,
                final-premium: coverage-adjusted,
                risk-factors: airline-modifier,
                seasonal-adjustment: (get-seasonal-multiplier (+ month u1))
            }
        )
        
        (var-set total-calculations (+ (var-get total-calculations) u1))
        (ok coverage-adjusted)
    )
)

(define-public (bulk-update-routes (route-data (list 50 {origin: (string-ascii 5), destination: (string-ascii 5), delayed: uint, total: uint, avg-delay: uint})))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (fold update-single-route route-data (ok true))
    )
)

(define-private (update-single-route
    (route-info {origin: (string-ascii 5), destination: (string-ascii 5), delayed: uint, total: uint, avg-delay: uint})
    (previous (response bool uint))
    )
    (match previous
        success (update-route-statistics
            (get origin route-info)
            (get destination route-info)
            (get total route-info)
            (get delayed route-info)
            (get avg-delay route-info)
        )
        error (err error)
    )
)

(define-public (set-base-premium-rate (rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> rate u0) ERR_INVALID_PARAMETERS)
        (var-set base-premium-rate rate)
        (ok true)
    )
)

(define-public (set-risk-weights
    (seasonal uint)
    (airline uint)
    (route uint)
    )
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (is-eq (+ seasonal airline route) u100) ERR_INVALID_PARAMETERS)
        
        (var-set seasonal-weight seasonal)
        (var-set airline-weight airline)
        (var-set route-weight route)
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-route-statistics (origin (string-ascii 5)) (destination (string-ascii 5)))
    (map-get? route-statistics {origin: origin, destination: destination})
)

(define-read-only (get-airline-performance (airline (string-ascii 10)))
    (map-get? airline-performance airline)
)

(define-read-only (get-seasonal-factors (month uint))
    (map-get? seasonal-factors month)
)

(define-read-only (get-premium-estimate
    (origin (string-ascii 5))
    (destination (string-ascii 5))
    (month uint)
    (coverage uint)
    )
    (let
        (
            (base-premium (calculate-route-premium origin destination))
            (seasonal-premium (apply-seasonal-adjustment base-premium month))
            (coverage-adjusted (/ (* seasonal-premium coverage) u100000))
        )
        (ok coverage-adjusted)
    )
)

(define-read-only (get-historical-premium (route-hash (buff 32)) (date uint))
    (map-get? historical-premiums {route-hash: route-hash, date: date})
)

(define-read-only (get-base-premium-rate)
    (var-get base-premium-rate)
)

(define-read-only (get-total-calculations)
    (var-get total-calculations)
)

(define-read-only (get-risk-weights)
    {
        seasonal: (var-get seasonal-weight),
        airline: (var-get airline-weight),
        route: (var-get route-weight)
    }
)
