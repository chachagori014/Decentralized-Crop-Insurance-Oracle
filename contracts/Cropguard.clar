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
(define-constant err-pool-not-found (err u111))
(define-constant err-pool-already-exists (err u112))
(define-constant err-invalid-pool-parameters (err u113))
(define-constant err-insufficient-pool-balance (err u114))
(define-constant err-max-pool-members-reached (err u115))
(define-constant err-not-pool-member (err u116))
(define-constant err-pool-withdrawal-limit (err u117))

(define-data-var next-policy-id uint u1)
(define-data-var total-policies uint u0)
(define-data-var total-claims-paid uint u0)
(define-data-var contract-balance uint u0)
(define-data-var next-pool-id uint u1)
(define-data-var total-pools uint u0)

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

(define-map insurance-pools
  { pool-id: uint }
  {
    pool-name: (string-ascii 50),
    pool-creator: principal,
    total-balance: uint,
    member-count: uint,
    max-members: uint,
    min-contribution: uint,
    risk-category: (string-ascii 30),
    coverage-multiplier: uint,
    pool-active: bool,
    created-block: uint
  }
)

(define-map pool-members
  { pool-id: uint, member: principal }
  {
    contribution-amount: uint,
    join-block: uint,
    is-active: bool,
    claims-received: uint,
    last-claim-block: uint
  }
)

(define-map pool-policies
  { pool-id: uint, policy-id: uint }
  { is-covered: bool }
)

(define-map member-pools
  { member: principal }
  { pool-ids: (list 50 uint) }
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
      
      ;; If weather conditions are met and contract has sufficient funds, process automatic payout
      (if (and weather-conditions-met (>= (var-get contract-balance) (get coverage-amount policy)))
        (match (process-automatic-payout policy-id)
          success (ok true)
          error (ok true) ;; Continue even if payout fails, claim is still recorded
        )
        (ok true) ;; Claim recorded for manual review
      )
    )
  )
)

(define-private (check-weather-conditions (policy-id uint))
  (let (
    (policy (unwrap! (map-get? policies { policy-id: policy-id }) false))
  )
    ;; For now, simulate weather condition checking
    ;; In a full implementation, this would:
    ;; 1. Query weather-data map for all entries matching policy-id
    ;; 2. Calculate average rainfall and maximum temperature from real data
    ;; 3. Compare against policy thresholds
    ;; For demo purposes, assume conditions are met if policy exists
    (is-some (map-get? policies { policy-id: policy-id }))
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
  ;; This would ideally iterate through weather-data map entries
  ;; For now, return empty list - in production, this should query the weather-data map
  ;; and collect rainfall values for the policy
  (list u0)
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

(define-public (create-insurance-pool
  (pool-name (string-ascii 50))
  (max-members uint)
  (min-contribution uint)
  (risk-category (string-ascii 30))
  (coverage-multiplier uint))
  (let (
    (pool-id (var-get next-pool-id))
    (current-block stacks-block-height)
  )
    (asserts! (> max-members u0) err-invalid-pool-parameters)
    (asserts! (> min-contribution u0) err-invalid-pool-parameters)
    (asserts! (> coverage-multiplier u0) err-invalid-pool-parameters)
    (asserts! (<= coverage-multiplier u5) err-invalid-pool-parameters)
    (asserts! (is-none (map-get? insurance-pools { pool-id: pool-id })) err-pool-already-exists)
    
    (map-set insurance-pools
      { pool-id: pool-id }
      {
        pool-name: pool-name,
        pool-creator: tx-sender,
        total-balance: u0,
        member-count: u0,
        max-members: max-members,
        min-contribution: min-contribution,
        risk-category: risk-category,
        coverage-multiplier: coverage-multiplier,
        pool-active: true,
        created-block: current-block
      }
    )
    
    (var-set next-pool-id (+ pool-id u1))
    (var-set total-pools (+ (var-get total-pools) u1))
    
    (ok pool-id)
  )
)

(define-public (join-insurance-pool (pool-id uint) (contribution-amount uint))
  (let (
    (pool (unwrap! (map-get? insurance-pools { pool-id: pool-id }) err-pool-not-found))
    (current-block stacks-block-height)
    (existing-member (map-get? pool-members { pool-id: pool-id, member: tx-sender }))
  )
    (asserts! (get pool-active pool) err-invalid-pool-parameters)
    (asserts! (>= contribution-amount (get min-contribution pool)) err-invalid-pool-parameters)
    (asserts! (< (get member-count pool) (get max-members pool)) err-max-pool-members-reached)
    (asserts! (>= (stx-get-balance tx-sender) contribution-amount) err-insufficient-balance)
    (asserts! (is-none existing-member) err-invalid-pool-parameters)
    
    (try! (stx-transfer? contribution-amount tx-sender (as-contract tx-sender)))
    
    (map-set pool-members
      { pool-id: pool-id, member: tx-sender }
      {
        contribution-amount: contribution-amount,
        join-block: current-block,
        is-active: true,
        claims-received: u0,
        last-claim-block: u0
      }
    )
    
    (map-set insurance-pools
      { pool-id: pool-id }
      (merge pool {
        total-balance: (+ (get total-balance pool) contribution-amount),
        member-count: (+ (get member-count pool) u1)
      })
    )
    
    (let ((current-pools (default-to (list) (get pool-ids (map-get? member-pools { member: tx-sender })))))
      (map-set member-pools
        { member: tx-sender }
        { pool-ids: (unwrap! (as-max-len? (append current-pools pool-id) u50) err-invalid-pool-parameters) }
      )
    )
    
    (ok true)
  )
)

(define-public (contribute-to-pool (pool-id uint) (additional-amount uint))
  (let (
    (pool (unwrap! (map-get? insurance-pools { pool-id: pool-id }) err-pool-not-found))
    (member-info (unwrap! (map-get? pool-members { pool-id: pool-id, member: tx-sender }) err-not-pool-member))
  )
    (asserts! (get pool-active pool) err-invalid-pool-parameters)
    (asserts! (get is-active member-info) err-not-pool-member)
    (asserts! (> additional-amount u0) err-invalid-pool-parameters)
    (asserts! (>= (stx-get-balance tx-sender) additional-amount) err-insufficient-balance)
    
    (try! (stx-transfer? additional-amount tx-sender (as-contract tx-sender)))
    
    (map-set pool-members
      { pool-id: pool-id, member: tx-sender }
      (merge member-info {
        contribution-amount: (+ (get contribution-amount member-info) additional-amount)
      })
    )
    
    (map-set insurance-pools
      { pool-id: pool-id }
      (merge pool {
        total-balance: (+ (get total-balance pool) additional-amount)
      })
    )
    
    (ok true)
  )
)

(define-public (create-pool-policy 
  (pool-id uint)
  (crop-type (string-ascii 50))
  (coverage-amount uint)
  (duration-blocks uint)
  (latitude int)
  (longitude int)
  (min-rainfall uint)
  (max-temperature uint))
  (let (
    (pool (unwrap! (map-get? insurance-pools { pool-id: pool-id }) err-pool-not-found))
    (member-info (unwrap! (map-get? pool-members { pool-id: pool-id, member: tx-sender }) err-not-pool-member))
    (policy-id (var-get next-policy-id))
    (pool-coverage (* coverage-amount (get coverage-multiplier pool)))
    (reduced-premium (/ coverage-amount u50))
    (current-block stacks-block-height)
    (end-block (+ current-block duration-blocks))
  )
    (asserts! (get pool-active pool) err-invalid-pool-parameters)
    (asserts! (get is-active member-info) err-not-pool-member)
    (asserts! (>= (get total-balance pool) pool-coverage) err-insufficient-pool-balance)
    (asserts! (>= (stx-get-balance tx-sender) reduced-premium) err-insufficient-balance)
    (asserts! (> coverage-amount u0) err-invalid-policy)
    (asserts! (> duration-blocks u0) err-invalid-policy)
    
    (try! (stx-transfer? reduced-premium tx-sender (as-contract tx-sender)))
    
    (map-set policies
      { policy-id: policy-id }
      {
        farmer: tx-sender,
        crop-type: crop-type,
        coverage-amount: pool-coverage,
        premium-paid: reduced-premium,
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
    
    (map-set pool-policies
      { pool-id: pool-id, policy-id: policy-id }
      { is-covered: true }
    )
    
    (let ((current-policies (default-to (list) (get policy-ids (map-get? farmer-policies { farmer: tx-sender })))))
      (map-set farmer-policies
        { farmer: tx-sender }
        { policy-ids: (unwrap! (as-max-len? (append current-policies policy-id) u100) err-invalid-policy) }
      )
    )
    
    (var-set next-policy-id (+ policy-id u1))
    (var-set total-policies (+ (var-get total-policies) u1))
    (var-set contract-balance (+ (var-get contract-balance) reduced-premium))
    
    (ok policy-id)
  )
)

(define-public (process-pool-claim (pool-id uint) (policy-id uint))
  (let (
    (pool (unwrap! (map-get? insurance-pools { pool-id: pool-id }) err-pool-not-found))
    (pool-policy (unwrap! (map-get? pool-policies { pool-id: pool-id, policy-id: policy-id }) err-policy-not-found))
    (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-policy-not-found))
    (member-info (unwrap! (map-get? pool-members { pool-id: pool-id, member: (get farmer policy) }) err-not-pool-member))
    (claim-request (unwrap! (map-get? claim-requests { policy-id: policy-id }) err-policy-not-found))
    (payout-amount (get coverage-amount policy))
    (current-block stacks-block-height)
  )
    (asserts! (get pool-active pool) err-invalid-pool-parameters)
    (asserts! (get is-covered pool-policy) err-policy-not-found)
    (asserts! (not (get processed claim-request)) err-claim-already-processed)
    (asserts! (get weather-conditions-met claim-request) err-invalid-weather-data)
    (asserts! (>= (get total-balance pool) payout-amount) err-insufficient-pool-balance)
    (asserts! (> (- current-block (get last-claim-block member-info)) u1440) err-pool-withdrawal-limit)
    
    (try! (as-contract (stx-transfer? payout-amount tx-sender (get farmer policy))))
    
    (map-set pool-members
      { pool-id: pool-id, member: (get farmer policy) }
      (merge member-info {
        claims-received: (+ (get claims-received member-info) u1),
        last-claim-block: current-block
      })
    )
    
    (map-set insurance-pools
      { pool-id: pool-id }
      (merge pool {
        total-balance: (- (get total-balance pool) payout-amount)
      })
    )
    
    (map-set policies
      { policy-id: policy-id }
      (merge policy { claim-processed: true, is-active: false })
    )
    
    (map-set claim-requests
      { policy-id: policy-id }
      (merge claim-request { processed: true })
    )
    
    (var-set total-claims-paid (+ (var-get total-claims-paid) payout-amount))
    
    (ok payout-amount)
  )
)

(define-read-only (get-insurance-pool (pool-id uint))
  (map-get? insurance-pools { pool-id: pool-id })
)

(define-read-only (get-pool-member (pool-id uint) (member principal))
  (map-get? pool-members { pool-id: pool-id, member: member })
)

(define-read-only (get-member-pools (member principal))
  (map-get? member-pools { member: member })
)

(define-read-only (get-pool-coverage (pool-id uint) (policy-id uint))
  (map-get? pool-policies { pool-id: pool-id, policy-id: policy-id })
)

(define-read-only (calculate-pool-premium (coverage-amount uint) (pool-multiplier uint))
  (/ coverage-amount (* u10 pool-multiplier))
)

(define-read-only (get-pool-stats)
  {
    total-pools: (var-get total-pools),
    next-pool-id: (var-get next-pool-id)
  }
)

