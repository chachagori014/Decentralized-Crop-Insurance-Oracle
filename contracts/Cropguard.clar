(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-policy (err u101))
(define-constant err-policy-not-found (err u102))
(define-constant err-insufficient-coverage (err u103))
(define-constant err-claim-already-processed (err u104))
(define-constant err-oracle-not-authorized (err u105))
(define-constant err-invalid-weather-data (err u106))
(define-constant err-policy-expired (err u107))
(define-constant err-claim-period-ended (err u108))
(define-constant err-insufficient-balance (err u109))
(define-constant err-policy-already-exists (err u110))

(define-data-var next-policy-id uint u1)
(define-data-var total-policies uint u0)
(define-data-var total-claims-paid uint u0)
(define-data-var contract-balance uint u0)

(define-map policies
  { policy-id: uint }
  {
    farmer: principal,
    crop-type: (string-ascii 50),
    coverage-amount: uint,
    premium-paid: uint,
    start-block: uint,
    end-block: uint,
    latitude: int,
    longitude: int,
    min-rainfall: uint,
    max-temperature: uint,
    is-active: bool,
    claim-processed: bool
  }
)

(define-map weather-data
  { policy-id: uint, data-timestamp: uint }
  {
    rainfall: uint,
    temperature: uint,
    humidity: uint,
    wind-speed: uint,
    oracle: principal,
    verified: bool
  }
)

(define-map authorized-oracles
  { oracle: principal }
  { is-authorized: bool }
)

(define-map farmer-policies
  { farmer: principal }
  { policy-ids: (list 100 uint) }
)

(define-map claim-requests
  { policy-id: uint }
  {
    claimed-by: principal,
    claim-amount: uint,
    weather-conditions-met: bool,
    processed: bool,
    approved: bool
  }
)

(define-public (create-policy 
  (crop-type (string-ascii 50))
  (coverage-amount uint)
  (duration-blocks uint)
  (latitude int)
  (longitude int)
  (min-rainfall uint)
  (max-temperature uint))
  (let (
    (policy-id (var-get next-policy-id))
    (premium (/ coverage-amount u20))
    (current-block stacks-block-height)
    (end-block (+ current-block duration-blocks))
  )
    (asserts! (>= (stx-get-balance tx-sender) premium) err-insufficient-balance)
    (asserts! (> coverage-amount u0) err-invalid-policy)
    (asserts! (> duration-blocks u0) err-invalid-policy)
    (asserts! (is-none (map-get? policies { policy-id: policy-id })) err-policy-already-exists)
    
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    (map-set policies
      { policy-id: policy-id }
      {
        farmer: tx-sender,
        crop-type: crop-type,
        coverage-amount: coverage-amount,
        premium-paid: premium,
        start-block: current-block,
        end-block: end-block,
        latitude: latitude,
        longitude: longitude,
        min-rainfall: min-rainfall,
        max-temperature: max-temperature,
        is-active: true,
        claim-processed: false
      }
    )
    
    (let ((current-policies (default-to (list) (get policy-ids (map-get? farmer-policies { farmer: tx-sender })))))
      (map-set farmer-policies
        { farmer: tx-sender }
        { policy-ids: (unwrap! (as-max-len? (append current-policies policy-id) u100) err-invalid-policy) }
      )
    )
    
    (var-set next-policy-id (+ policy-id u1))
    (var-set total-policies (+ (var-get total-policies) u1))
    (var-set contract-balance (+ (var-get contract-balance) premium))
    
    (ok policy-id)
  )
)

(define-public (submit-weather-data
  (policy-id uint)
  (rainfall uint)
  (temperature uint)
  (humidity uint)
  (wind-speed uint))
  (let (
    (oracle-authorized (default-to false (get is-authorized (map-get? authorized-oracles { oracle: tx-sender }))))
    (current-timestamp (unwrap! (get-stacks-block-info? time stacks-block-height) err-invalid-weather-data))
  )
    (asserts! oracle-authorized err-oracle-not-authorized)
    (asserts! (is-some (map-get? policies { policy-id: policy-id })) err-policy-not-found)
    
    (map-set weather-data
      { policy-id: policy-id, data-timestamp: current-timestamp }
      {
        rainfall: rainfall,
        temperature: temperature,
        humidity: humidity,
        wind-speed: wind-speed,
        oracle: tx-sender,
        verified: true
      }
    )
    
    (ok true)
  )
)

(define-public (submit-claim (policy-id uint))
  (let (
    (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-policy-not-found))
    (current-block stacks-block-height)
  )
    (asserts! (is-eq (get farmer policy) tx-sender) err-owner-only)
    (asserts! (get is-active policy) err-invalid-policy)
    (asserts! (not (get claim-processed policy)) err-claim-already-processed)
    (asserts! (>= current-block (get start-block policy)) err-invalid-policy)
    (asserts! (<= current-block (get end-block policy)) err-policy-expired)
    
    (let ((weather-conditions-met (check-weather-conditions policy-id)))
      (map-set claim-requests
        { policy-id: policy-id }
        {
          claimed-by: tx-sender,
          claim-amount: (get coverage-amount policy),
          weather-conditions-met: weather-conditions-met,
          processed: false,
          approved: weather-conditions-met
        }
      )
      

    )
    
    (ok true)
  )
)

(define-private (check-weather-conditions (policy-id uint))
  (let (
    (policy (unwrap! (map-get? policies { policy-id: policy-id }) false))
    (weather-entries (get-weather-data-for-policy policy-id))
  )
    (if (> (len weather-entries) u0)
      (let (
        (avg-rainfall (calculate-average-rainfall weather-entries))
      )
        (or 
          (< avg-rainfall (get min-rainfall policy))
          (> u37 (get max-temperature policy))
        )
      )
      false
    )
  )
)

(define-private (process-automatic-payout (policy-id uint))
  (let (
    (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-policy-not-found))
    (payout-amount (get coverage-amount policy))
  )
    (asserts! (>= (var-get contract-balance) payout-amount) err-insufficient-coverage)
    
    (try! (as-contract (stx-transfer? payout-amount tx-sender (get farmer policy))))
    
    (map-set policies
      { policy-id: policy-id }
      (merge policy { claim-processed: true, is-active: false })
    )
    
    (map-set claim-requests
      { policy-id: policy-id }
      (merge (unwrap! (map-get? claim-requests { policy-id: policy-id }) err-invalid-policy) { processed: true })
    )
    
    (var-set total-claims-paid (+ (var-get total-claims-paid) payout-amount))
    (var-set contract-balance (- (var-get contract-balance) payout-amount))
    
    (ok payout-amount)
  )
)

(define-public (authorize-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-oracles { oracle: oracle } { is-authorized: true })
    (ok true)
  )
)

(define-public (revoke-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-oracles { oracle: oracle } { is-authorized: false })
    (ok true)
  )
)

(define-public (fund-contract)
  (let ((amount (stx-get-balance tx-sender)))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) amount))
    (ok amount)
  )
)

(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

(define-read-only (get-farmer-policies (farmer principal))
  (map-get? farmer-policies { farmer: farmer })
)

(define-read-only (get-weather-data (policy-id uint) (timestamp uint))
  (map-get? weather-data { policy-id: policy-id, data-timestamp: timestamp })
)

(define-read-only (get-claim-request (policy-id uint))
  (map-get? claim-requests { policy-id: policy-id })
)

(define-read-only (is-oracle-authorized (oracle principal))
  (default-to false (get is-authorized (map-get? authorized-oracles { oracle: oracle })))
)

(define-read-only (get-contract-stats)
  {
    total-policies: (var-get total-policies),
    total-claims-paid: (var-get total-claims-paid),
    contract-balance: (var-get contract-balance),
    next-policy-id: (var-get next-policy-id)
  }
)

(define-read-only (calculate-premium (coverage-amount uint))
  (/ coverage-amount u20)
)

(define-private (get-weather-data-for-policy (policy-id uint))
  (list)
)

(define-private (calculate-average-rainfall (weather-entries (list 100 uint)))
  (if (> (len weather-entries) u0)
    (/ (fold + weather-entries u0) (len weather-entries))
    u0
  )
)



(define-read-only (get-policy-status (policy-id uint))
  (let ((policy (map-get? policies { policy-id: policy-id })))
    (if (is-some policy)
      (let (
        (p (unwrap-panic policy))
        (current-block stacks-block-height)
      )
        {
          exists: true,
          is-active: (get is-active p),
          expired: (> current-block (get end-block p)),
          claim-processed: (get claim-processed p),
          blocks-remaining: (if (> (get end-block p) current-block) (- (get end-block p) current-block) u0)
        }
      )
      { exists: false, is-active: false, expired: false, claim-processed: false, blocks-remaining: u0 }
    )
  )
)
