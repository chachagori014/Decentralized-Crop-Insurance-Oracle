;; Dynamic Risk Assessment and Premium Adjustment Engine
;; Calculates dynamic premiums based on regional risk patterns, farmer history, and seasonal trends

(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u200))
(define-constant err-invalid-region (err u201))
(define-constant err-invalid-parameters (err u202))
(define-constant err-region-not-found (err u203))
(define-constant err-insufficient-data (err u204))
(define-constant err-farmer-not-found (err u205))
(define-constant err-invalid-season (err u206))
(define-constant err-calculation-error (err u207))

;; Risk multiplier constants (basis points, 10000 = 100%)
(define-constant base-risk-multiplier u10000)
(define-constant max-risk-multiplier u25000)
(define-constant min-risk-multiplier u5000)

;; Data variables for system-wide risk tracking
(define-data-var total-regions uint u0)
(define-data-var next-region-id uint u1)
(define-data-var global-base-premium uint u500) ;; Base premium in microSTX per coverage unit
(define-data-var risk-calculation-blocks uint u2160) ;; Blocks to analyze for risk (approx 15 days)

;; Regional risk data storage
(define-map regional-risks
  { region-id: uint }
  {
    region-name: (string-ascii 50),
    latitude-center: int,
    longitude-center: int,
    radius-km: uint,
    total-policies: uint,
    total-claims: uint,
    total-payouts: uint,
    avg-rainfall: uint,
    avg-temperature: uint,
    risk-score: uint, ;; 0-10000 scale
    last-updated-block: uint,
    is-active: bool
  }
)

;; Farmer risk profiles
(define-map farmer-risk-profiles
  { farmer: principal }
  {
    total-policies-created: uint,
    successful-policies: uint,
    total-claims-submitted: uint,
    approved-claims: uint,
    total-premiums-paid: uint,
    total-payouts-received: uint,
    risk-tier: uint, ;; 1=excellent, 2=good, 3=average, 4=high-risk, 5=very-high-risk
    reliability-score: uint, ;; 0-10000 scale
    last-policy-block: uint,
    consecutive-no-claims: uint
  }
)

;; Seasonal risk adjustments
(define-map seasonal-risks
  { season: uint, crop-type: (string-ascii 50) }
  {
    season-name: (string-ascii 20),
    risk-multiplier: uint, ;; basis points
    historical-claims: uint,
    weather-volatility: uint,
    optimal-planting: bool
  }
)

;; Weather pattern tracking
(define-map weather-patterns
  { region-id: uint, pattern-type: (string-ascii 20) }
  {
    frequency: uint,
    severity: uint,
    last-occurrence-block: uint,
    impact-score: uint
  }
)

;; Premium calculation history
(define-map premium-calculations
  { farmer: principal, calculation-id: uint }
  {
    base-premium: uint,
    regional-adjustment: uint,
    farmer-adjustment: uint,
    seasonal-adjustment: uint,
    final-premium: uint,
    calculated-block: uint,
    risk-factors: (string-ascii 200)
  }
)

;; Initialize a new region for risk tracking
(define-public (register-risk-region 
  (region-name (string-ascii 50))
  (latitude-center int)
  (longitude-center int)
  (radius-km uint))
  (let (
    (region-id (var-get next-region-id))
  )
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (> radius-km u0) err-invalid-parameters)
    (asserts! (<= radius-km u500) err-invalid-parameters)
    
    (map-set regional-risks
      { region-id: region-id }
      {
        region-name: region-name,
        latitude-center: latitude-center,
        longitude-center: longitude-center,
        radius-km: radius-km,
        total-policies: u0,
        total-claims: u0,
        total-payouts: u0,
        avg-rainfall: u0,
        avg-temperature: u0,
        risk-score: u5000, ;; Start with neutral risk
        last-updated-block: stacks-block-height,
        is-active: true
      }
    )
    
    (var-set next-region-id (+ region-id u1))
    (var-set total-regions (+ (var-get total-regions) u1))
    
    (ok region-id)
  )
)

;; Update regional risk data based on new claims and weather data
(define-public (update-regional-risk 
  (region-id uint)
  (new-policies uint)
  (new-claims uint)
  (new-payouts uint)
  (avg-rainfall uint)
  (avg-temperature uint))
  (let (
    (existing-region (unwrap! (map-get? regional-risks { region-id: region-id }) err-region-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (get is-active existing-region) err-invalid-region)
    
    (let (
      (updated-policies (+ (get total-policies existing-region) new-policies))
      (updated-claims (+ (get total-claims existing-region) new-claims))
      (updated-payouts (+ (get total-payouts existing-region) new-payouts))
      (claim-rate (if (> updated-policies u0) (/ (* updated-claims u10000) updated-policies) u0))
      (new-risk-score (calculate-regional-risk-score claim-rate avg-rainfall avg-temperature))
    )
      (map-set regional-risks
        { region-id: region-id }
        (merge existing-region {
          total-policies: updated-policies,
          total-claims: updated-claims,
          total-payouts: updated-payouts,
          avg-rainfall: avg-rainfall,
          avg-temperature: avg-temperature,
          risk-score: new-risk-score,
          last-updated-block: stacks-block-height
        })
      )
      
      (ok new-risk-score)
    )
  )
)

;; Update farmer risk profile
(define-public (update-farmer-profile 
  (farmer principal)
  (new-policy bool)
  (policy-success bool)
  (claim-submitted bool)
  (claim-approved bool)
  (premium-paid uint)
  (payout-received uint))
  (let (
    (existing-profile (default-to 
      {
        total-policies-created: u0,
        successful-policies: u0,
        total-claims-submitted: u0,
        approved-claims: u0,
        total-premiums-paid: u0,
        total-payouts-received: u0,
        risk-tier: u3, ;; Start at average
        reliability-score: u5000, ;; Neutral
        last-policy-block: u0,
        consecutive-no-claims: u0
      }
      (map-get? farmer-risk-profiles { farmer: farmer })
    ))
  )
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    
    (let (
      (updated-policies (if new-policy (+ (get total-policies-created existing-profile) u1) (get total-policies-created existing-profile)))
      (updated-successful (if (and new-policy policy-success) (+ (get successful-policies existing-profile) u1) (get successful-policies existing-profile)))
      (updated-claims (if claim-submitted (+ (get total-claims-submitted existing-profile) u1) (get total-claims-submitted existing-profile)))
      (updated-approved (if (and claim-submitted claim-approved) (+ (get approved-claims existing-profile) u1) (get approved-claims existing-profile)))
      (updated-premiums (+ (get total-premiums-paid existing-profile) premium-paid))
      (updated-payouts (+ (get total-payouts-received existing-profile) payout-received))
      (consecutive-no-claims (if claim-submitted u0 (+ (get consecutive-no-claims existing-profile) u1)))
      (reliability-score (calculate-farmer-reliability updated-policies updated-successful updated-claims updated-approved consecutive-no-claims))
      (risk-tier (get-risk-tier-from-score reliability-score))
    )
      (map-set farmer-risk-profiles
        { farmer: farmer }
        {
          total-policies-created: updated-policies,
          successful-policies: updated-successful,
          total-claims-submitted: updated-claims,
          approved-claims: updated-approved,
          total-premiums-paid: updated-premiums,
          total-payouts-received: updated-payouts,
          risk-tier: risk-tier,
          reliability-score: reliability-score,
          last-policy-block: (if new-policy stacks-block-height (get last-policy-block existing-profile)),
          consecutive-no-claims: consecutive-no-claims
        }
      )
      
      (ok reliability-score)
    )
  )
)

;; Set seasonal risk multipliers
(define-public (set-seasonal-risk 
  (season uint)
  (crop-type (string-ascii 50))
  (season-name (string-ascii 20))
  (risk-multiplier uint)
  (historical-claims uint)
  (weather-volatility uint)
  (optimal-planting bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (<= season u4) err-invalid-season) ;; 1-4 for seasons
    (asserts! (>= risk-multiplier u5000) err-invalid-parameters) ;; Min 50%
    (asserts! (<= risk-multiplier u20000) err-invalid-parameters) ;; Max 200%
    
    (map-set seasonal-risks
      { season: season, crop-type: crop-type }
      {
        season-name: season-name,
        risk-multiplier: risk-multiplier,
        historical-claims: historical-claims,
        weather-volatility: weather-volatility,
        optimal-planting: optimal-planting
      }
    )
    
    (ok true)
  )
)

;; Calculate dynamic premium for a farmer
(define-public (calculate-dynamic-premium 
  (farmer principal)
  (coverage-amount uint)
  (region-id uint)
  (crop-type (string-ascii 50))
  (season uint))
  (let (
    (base-premium (/ (* coverage-amount (var-get global-base-premium)) u100000))
    (regional-data (unwrap! (map-get? regional-risks { region-id: region-id }) err-region-not-found))
    (farmer-profile (default-to 
      {
        total-policies-created: u0,
        successful-policies: u0,
        total-claims-submitted: u0,
        approved-claims: u0,
        total-premiums-paid: u0,
        total-payouts-received: u0,
        risk-tier: u3,
        reliability-score: u5000,
        last-policy-block: u0,
        consecutive-no-claims: u0
      }
      (map-get? farmer-risk-profiles { farmer: farmer })
    ))
    (seasonal-data (default-to
      {
        season-name: "default",
        risk-multiplier: u10000,
        historical-claims: u0,
        weather-volatility: u0,
        optimal-planting: true
      }
      (map-get? seasonal-risks { season: season, crop-type: crop-type })
    ))
  )
    (asserts! (get is-active regional-data) err-invalid-region)
    
    (let (
      (regional-multiplier (/ (get risk-score regional-data) u100)) ;; Convert to basis points
      (farmer-multiplier (calculate-farmer-multiplier (get risk-tier farmer-profile) (get consecutive-no-claims farmer-profile)))
      (seasonal-multiplier (get risk-multiplier seasonal-data))
      (combined-multiplier (/ (* (* regional-multiplier farmer-multiplier) seasonal-multiplier) u100000000)) ;; Normalize
      (capped-multiplier (if (> combined-multiplier max-risk-multiplier) max-risk-multiplier 
                          (if (< combined-multiplier min-risk-multiplier) min-risk-multiplier combined-multiplier)))
      (final-premium (/ (* base-premium capped-multiplier) u10000))
      (calculation-id (+ (get total-policies-created farmer-profile) u1))
    )
      ;; Store calculation for audit trail
      (map-set premium-calculations
        { farmer: farmer, calculation-id: calculation-id }
        {
          base-premium: base-premium,
          regional-adjustment: regional-multiplier,
          farmer-adjustment: farmer-multiplier,
          seasonal-adjustment: seasonal-multiplier,
          final-premium: final-premium,
          calculated-block: stacks-block-height,
          risk-factors: "calculated"
        }
      )
      
      (ok final-premium)
    )
  )
)

;; Private helper functions

(define-private (calculate-regional-risk-score (claim-rate uint) (avg-rainfall uint) (avg-temperature uint))
  (let (
    (rainfall-risk (if (< avg-rainfall u300) u8000 (if (> avg-rainfall u1200) u7000 u5000)))
    (temp-risk (if (> avg-temperature u35) u8000 (if (< avg-temperature u10) u7000 u5000)))
    (claim-risk (if (> claim-rate u3000) u9000 (if (> claim-rate u1500) u7000 u4000)))
  )
    (/ (+ (+ rainfall-risk temp-risk) claim-risk) u3)
  )
)

(define-private (calculate-farmer-reliability 
  (total-policies uint)
  (successful-policies uint)
  (total-claims uint)
  (approved-claims uint)
  (consecutive-no-claims uint))
  (if (is-eq total-policies u0)
    u5000 ;; Neutral for new farmers
    (let (
      (success-rate (if (> total-policies u0) (/ (* successful-policies u10000) total-policies) u0))
      (claim-rate (if (> total-policies u0) (/ (* total-claims u10000) total-policies) u0))
      (approval-rate (if (> total-claims u0) (/ (* approved-claims u10000) total-claims) u10000))
      (no-claim-bonus (if (> consecutive-no-claims u5) u1500 (if (> consecutive-no-claims u2) u500 u0)))
    )
      (let (
        (base-score (/ (+ success-rate approval-rate) u2))
        (claim-penalty (if (> claim-rate u2000) u1000 u0))
        (final-score (+ (- base-score claim-penalty) no-claim-bonus))
      )
        (if (> final-score u10000) u10000 final-score)
      )
    )
  )
)

(define-private (get-risk-tier-from-score (reliability-score uint))
  (if (>= reliability-score u8500) u1      ;; Excellent
    (if (>= reliability-score u7000) u2    ;; Good  
      (if (>= reliability-score u5000) u3  ;; Average
        (if (>= reliability-score u3000) u4 ;; High-risk
          u5)))))                          ;; Very high-risk

(define-private (calculate-farmer-multiplier (risk-tier uint) (consecutive-no-claims uint))
  (let (
    (tier-multiplier (if (is-eq risk-tier u1) u8000      ;; 20% discount for excellent
                      (if (is-eq risk-tier u2) u9000     ;; 10% discount for good
                        (if (is-eq risk-tier u3) u10000  ;; No adjustment for average
                          (if (is-eq risk-tier u4) u12000 ;; 20% premium for high-risk
                            u15000)))))                  ;; 50% premium for very high-risk
    (no-claim-discount (if (> consecutive-no-claims u10) u1500
                        (if (> consecutive-no-claims u5) u1000
                          (if (> consecutive-no-claims u2) u500 u0))))
  )
    (- tier-multiplier no-claim-discount)
  )
)

;; Read-only functions for data access

(define-read-only (get-regional-risk (region-id uint))
  (map-get? regional-risks { region-id: region-id })
)

(define-read-only (get-farmer-profile (farmer principal))
  (map-get? farmer-risk-profiles { farmer: farmer })
)

(define-read-only (get-seasonal-risk (season uint) (crop-type (string-ascii 50)))
  (map-get? seasonal-risks { season: season, crop-type: crop-type })
)

(define-read-only (get-premium-calculation (farmer principal) (calculation-id uint))
  (map-get? premium-calculations { farmer: farmer, calculation-id: calculation-id })
)

(define-read-only (get-system-stats)
  {
    total-regions: (var-get total-regions),
    next-region-id: (var-get next-region-id),
    global-base-premium: (var-get global-base-premium),
    risk-calculation-blocks: (var-get risk-calculation-blocks)
  }
)

;; Admin functions

(define-public (update-global-base-premium (new-premium uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (> new-premium u0) err-invalid-parameters)
    (var-set global-base-premium new-premium)
    (ok true)
  )
)

(define-public (deactivate-region (region-id uint))
  (let (
    (existing-region (unwrap! (map-get? regional-risks { region-id: region-id }) err-region-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (map-set regional-risks
      { region-id: region-id }
      (merge existing-region { is-active: false })
    )
    (ok true)
  )
)
