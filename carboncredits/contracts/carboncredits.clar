;; Carbon Credits - Decentralized Environmental Impact Marketplace
;; Tokenize and trade verified carbon offsets on the Stacks blockchain

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-not-authorized (err u301))
(define-constant err-credit-not-found (err u302))
(define-constant err-invalid-amount (err u303))
(define-constant err-already-retired (err u304))
(define-constant err-not-validator (err u305))
(define-constant err-listing-not-found (err u306))
(define-constant err-not-listed (err u307))
(define-constant err-insufficient-payment (err u308))
(define-constant err-cannot-buy-own (err u309))
(define-constant err-marketplace-paused (err u310))
(define-constant err-invalid-credit-id (err u311))
(define-constant err-already-listed (err u312))
(define-constant err-invalid-price (err u313))
(define-constant err-batch-too-large (err u314))

;; Data Variables
(define-data-var marketplace-paused bool false)
(define-data-var total-credits-minted uint u0)
(define-data-var total-credits-retired uint u0)
(define-data-var total-co2-offset uint u0)
(define-data-var total-marketplace-volume uint u0)
(define-data-var marketplace-fee-percentage uint u250) ;; 2.5% fee in basis points

;; Data Maps

;; Carbon credit storage (NFT-like structure)
(define-map carbon-credits
  uint  ;; credit-id
  {
    owner: principal,
    tons-co2: uint,
    project-name: (string-ascii 200),
    project-type: (string-ascii 20),
    minted-at: uint,
    minted-by: principal,
    retired: bool,
    retired-at: (optional uint),
    retired-by: (optional principal)
  }
)

;; Marketplace listings
(define-map credit-listings
  uint  ;; credit-id
  {
    seller: principal,
    price: uint,
    listed-at: uint,
    active: bool
  }
)

;; Approved validators (can mint credits)
(define-map validators principal bool)

;; User profiles and statistics
(define-map user-profiles
  principal
  {
    credits-minted: uint,
    credits-owned: uint,
    credits-retired: uint,
    total-co2-offset: uint,
    total-volume-traded: uint,
    reputation-score: uint
  }
)

;; Price history for analytics
(define-map credit-price-history
  { credit-id: uint, sale-number: uint }
  {
    price: uint,
    timestamp: uint,
    seller: principal,
    buyer: principal
  }
)

(define-map credit-sale-count uint uint)

;; Private Functions

(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (is-credit-owner (credit-id uint) (user principal))
  (match (map-get? carbon-credits credit-id)
    credit (is-eq (get owner credit) user)
    false
  )
)

(define-private (get-or-create-profile (user principal))
  (default-to
    {
      credits-minted: u0,
      credits-owned: u0,
      credits-retired: u0,
      total-co2-offset: u0,
      total-volume-traded: u0,
      reputation-score: u1000
    }
    (map-get? user-profiles user)
  )
)

(define-private (update-profile-on-mint (validator principal) (tons uint))
  (let
    (
      (profile (get-or-create-profile validator))
    )
    (map-set user-profiles validator
      (merge profile {
        credits-minted: (+ (get credits-minted profile) u1),
        credits-owned: (+ (get credits-owned profile) u1)
      })
    )
  )
)

(define-private (update-profile-on-retirement (user principal) (tons uint))
  (let
    (
      (profile (get-or-create-profile user))
      (new-rep (+ (get reputation-score profile) (/ tons u10)))
    )
    (map-set user-profiles user
      (merge profile {
        credits-retired: (+ (get credits-retired profile) u1),
        total-co2-offset: (+ (get total-co2-offset profile) tons),
        reputation-score: (if (> new-rep u10000) u10000 new-rep)
      })
    )
  )
)

(define-private (calculate-marketplace-fee (price uint))
  (/ (* price (var-get marketplace-fee-percentage)) u10000)
)

(define-private (transfer-credit-ownership (credit-id uint) (from principal) (to principal))
  (let
    (
      (from-profile (get-or-create-profile from))
      (to-profile (get-or-create-profile to))
    )
    (map-set user-profiles from
      (merge from-profile {
        credits-owned: (if (> (get credits-owned from-profile) u0)
          (- (get credits-owned from-profile) u1)
          u0
        )
      })
    )
    (map-set user-profiles to
      (merge to-profile {
        credits-owned: (+ (get credits-owned to-profile) u1)
      })
    )
    true
  )
)

(define-private (record-sale (credit-id uint) (price uint) (seller principal) (buyer principal))
  (let
    (
      (sale-count (default-to u0 (map-get? credit-sale-count credit-id)))
    )
    (map-set credit-price-history
      { credit-id: credit-id, sale-number: sale-count }
      {
        price: price,
        timestamp: stacks-block-height,
        seller: seller,
        buyer: buyer
      }
    )
    (map-set credit-sale-count credit-id (+ sale-count u1))
  )
)

(define-private (get-credit-tons (credit-id uint))
  (match (map-get? carbon-credits credit-id)
    credit (get tons-co2 credit)
    u0
  )
)

(define-private (retire-single-credit (credit-id uint))
  (retire-credit credit-id)
)

;; Public Functions

;; Mint new carbon credits (validators only)
(define-public (mint-carbon-credit (tons-co2 uint) (project-name (string-ascii 200)) (project-type (string-ascii 20)))
  (let
    (
      (credit-id (var-get total-credits-minted))
      (minter tx-sender)
    )
    ;; Validations
    (asserts! (not (var-get marketplace-paused)) err-marketplace-paused)
    (asserts! (default-to false (map-get? validators minter)) err-not-validator)
    (asserts! (> tons-co2 u0) err-invalid-amount)
    (asserts! (> (len project-name) u0) err-invalid-amount)
    (asserts! (> (len project-type) u0) err-invalid-amount)
    
    ;; Create credit
    (map-set carbon-credits credit-id
      {
        owner: minter,
        tons-co2: tons-co2,
        project-name: project-name,
        project-type: project-type,
        minted-at: stacks-block-height,
        minted-by: minter,
        retired: false,
        retired-at: none,
        retired-by: none
      }
    )
    
    ;; Update counters
    (var-set total-credits-minted (+ credit-id u1))
    (var-set total-co2-offset (+ (var-get total-co2-offset) tons-co2))
    
    ;; Update profile
    (update-profile-on-mint minter tons-co2)
    
    (ok credit-id)
  )
)

;; Transfer credit to another user
(define-public (transfer-credit (credit-id uint) (recipient principal))
  (let
    (
      (credit (unwrap! (map-get? carbon-credits credit-id) err-credit-not-found))
      (sender tx-sender)
    )
    ;; Validations
    (asserts! (not (var-get marketplace-paused)) err-marketplace-paused)
    (asserts! (is-eq (get owner credit) sender) err-not-authorized)
    (asserts! (not (get retired credit)) err-already-retired)
    (asserts! (not (is-eq sender recipient)) err-not-authorized)
    
    ;; Check if listed, delist if so
    (match (map-get? credit-listings credit-id)
      listing (if (get active listing)
        (map-set credit-listings credit-id (merge listing { active: false }))
        true
      )
      true
    )
    
    ;; Update credit owner
    (map-set carbon-credits credit-id
      (merge credit { owner: recipient })
    )
    
    ;; Update profiles
    (transfer-credit-ownership credit-id sender recipient)
    
    (ok true)
  )
)

;; Retire (burn) credit to claim environmental offset
(define-public (retire-credit (credit-id uint))
  (let
    (
      (credit (unwrap! (map-get? carbon-credits credit-id) err-credit-not-found))
      (owner tx-sender)
      (tons (get tons-co2 credit))
    )
    ;; Validations
    (asserts! (not (var-get marketplace-paused)) err-marketplace-paused)
    (asserts! (is-eq (get owner credit) owner) err-not-authorized)
    (asserts! (not (get retired credit)) err-already-retired)
    
    ;; Delist if listed
    (match (map-get? credit-listings credit-id)
      listing (if (get active listing)
        (map-set credit-listings credit-id (merge listing { active: false }))
        true
      )
      true
    )
    
    ;; Mark as retired
    (map-set carbon-credits credit-id
      (merge credit {
        retired: true,
        retired-at: (some stacks-block-height),
        retired-by: (some owner)
      })
    )
    
    ;; Update counters
    (var-set total-credits-retired (+ (var-get total-credits-retired) u1))
    
    ;; Update profile
    (update-profile-on-retirement owner tons)
    
    (ok { credit-id: credit-id, tons-offset: tons })
  )
)

;; Batch retire multiple credits
(define-public (batch-retire-credits (credit-ids (list 20 uint)))
  (let
    (
      (total-tons (fold + (map get-credit-tons credit-ids) u0))
    )
    (asserts! (<= (len credit-ids) u20) err-batch-too-large)
    (asserts! (> (len credit-ids) u0) err-invalid-amount)
    
    ;; Process each retirement
    (map retire-single-credit credit-ids)
    
    (ok { retired-count: (len credit-ids), total-tons: total-tons })
  )
)

;; List credit for sale on marketplace
(define-public (list-credit-for-sale (credit-id uint) (price uint))
  (let
    (
      (credit (unwrap! (map-get? carbon-credits credit-id) err-credit-not-found))
      (seller tx-sender)
    )
    ;; Validations
    (asserts! (not (var-get marketplace-paused)) err-marketplace-paused)
    (asserts! (is-eq (get owner credit) seller) err-not-authorized)
    (asserts! (not (get retired credit)) err-already-retired)
    (asserts! (> price u0) err-invalid-price)
    (asserts! (>= price u1000000) err-invalid-price) ;; Minimum 1 STX
    
    ;; Check not already listed
    (match (map-get? credit-listings credit-id)
      listing (asserts! (not (get active listing)) err-already-listed)
      true
    )
    
    ;; Create listing
    (map-set credit-listings credit-id
      {
        seller: seller,
        price: price,
        listed-at: stacks-block-height,
        active: true
      }
    )
    
    (ok true)
  )
)

;; Cancel marketplace listing
(define-public (cancel-listing (credit-id uint))
  (let
    (
      (listing (unwrap! (map-get? credit-listings credit-id) err-listing-not-found))
      (seller tx-sender)
    )
    ;; Validations
    (asserts! (is-eq (get seller listing) seller) err-not-authorized)
    (asserts! (get active listing) err-not-listed)
    
    ;; Deactivate listing
    (map-set credit-listings credit-id
      (merge listing { active: false })
    )
    
    (ok true)
  )
)

;; Buy credit from marketplace
(define-public (buy-credit (credit-id uint))
  (let
    (
      (credit (unwrap! (map-get? carbon-credits credit-id) err-credit-not-found))
      (listing (unwrap! (map-get? credit-listings credit-id) err-listing-not-found))
      (buyer tx-sender)
      (seller (get seller listing))
      (price (get price listing))
      (fee (calculate-marketplace-fee price))
      (seller-amount (- price fee))
    )
    ;; Validations
    (asserts! (not (var-get marketplace-paused)) err-marketplace-paused)
    (asserts! (get active listing) err-not-listed)
    (asserts! (not (is-eq buyer seller)) err-cannot-buy-own)
    (asserts! (not (get retired credit)) err-already-retired)
    
    ;; Transfer payment to seller
    (try! (stx-transfer? seller-amount buyer seller))
    
    ;; Transfer fee to contract
    (if (> fee u0)
      (try! (stx-transfer? fee buyer (as-contract tx-sender)))
      true
    )
    
    ;; Update credit ownership
    (map-set carbon-credits credit-id
      (merge credit { owner: buyer })
    )
    
    ;; Deactivate listing
    (map-set credit-listings credit-id
      (merge listing { active: false })
    )
    
    ;; Update profiles
    (transfer-credit-ownership credit-id seller buyer)
    
    ;; Record sale
    (record-sale credit-id price seller buyer)
    
    ;; Update marketplace volume
    (var-set total-marketplace-volume (+ (var-get total-marketplace-volume) price))
    
    (ok { credit-id: credit-id, price: price, fee: fee })
  )
)

;; Update listing price
(define-public (update-listing-price (credit-id uint) (new-price uint))
  (let
    (
      (listing (unwrap! (map-get? credit-listings credit-id) err-listing-not-found))
      (seller tx-sender)
    )
    ;; Validations
    (asserts! (is-eq (get seller listing) seller) err-not-authorized)
    (asserts! (get active listing) err-not-listed)
    (asserts! (> new-price u0) err-invalid-price)
    (asserts! (>= new-price u1000000) err-invalid-price)
    
    ;; Update price
    (map-set credit-listings credit-id
      (merge listing { price: new-price })
    )
    
    (ok true)
  )
)

;; Administrative Functions

;; Add validator
(define-public (add-validator (validator principal))
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (map-set validators validator true)
    (ok true)
  )
)

;; Remove validator
(define-public (remove-validator (validator principal))
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (map-set validators validator false)
    (ok true)
  )
)

;; Update marketplace fee
(define-public (set-marketplace-fee (new-fee uint))
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (asserts! (<= new-fee u1000) err-invalid-amount) ;; Max 10%
    (var-set marketplace-fee-percentage new-fee)
    (ok true)
  )
)

;; Pause marketplace
(define-public (pause-marketplace)
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (var-set marketplace-paused true)
    (ok true)
  )
)

;; Resume marketplace
(define-public (resume-marketplace)
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (var-set marketplace-paused false)
    (ok true)
  )
)

;; Withdraw accumulated fees (owner only)
(define-public (withdraw-fees (amount uint))
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (as-contract (stx-transfer? amount tx-sender contract-owner))
  )
)

;; Read-Only Functions

(define-read-only (get-credit-details (credit-id uint))
  (map-get? carbon-credits credit-id)
)

(define-read-only (get-listing-details (credit-id uint))
  (map-get? credit-listings credit-id)
)

(define-read-only (get-user-profile (user principal))
  (get-or-create-profile user)
)

(define-read-only (is-validator (user principal))
  (default-to false (map-get? validators user))
)

(define-read-only (get-marketplace-stats)
  {
    total-minted: (var-get total-credits-minted),
    total-retired: (var-get total-credits-retired),
    total-co2-offset: (var-get total-co2-offset),
    marketplace-volume: (var-get total-marketplace-volume),
    is-paused: (var-get marketplace-paused),
    fee-percentage: (var-get marketplace-fee-percentage)
  }
)

(define-read-only (get-total-retired-by-user (user principal))
  (let
    (
      (profile (get-or-create-profile user))
    )
    (get total-co2-offset profile)
  )
)

(define-read-only (get-credit-price-history (credit-id uint))
  (let
    (
      (sale-count (default-to u0 (map-get? credit-sale-count credit-id)))
    )
    {
      total-sales: sale-count,
      credit-id: credit-id
    }
  )
)

(define-read-only (get-sale-details (credit-id uint) (sale-number uint))
  (map-get? credit-price-history { credit-id: credit-id, sale-number: sale-number })
)

(define-read-only (is-credit-listed (credit-id uint))
  (match (map-get? credit-listings credit-id)
    listing (get active listing)
    false
  )
)

(define-read-only (is-credit-retired (credit-id uint))
  (match (map-get? carbon-credits credit-id)
    credit (get retired credit)
    false
  )
)

(define-read-only (calculate-offset-value (tons-co2 uint) (price-per-ton uint))
  (* tons-co2 price-per-ton)
)

(define-read-only (get-user-reputation-score (user principal))
  (let
    (
      (profile (get-or-create-profile user))
    )
    (get reputation-score profile)
  )
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-credits-minted-count)
  (var-get total-credits-minted)
)

(define-read-only (get-credits-retired-count)
  (var-get total-credits-retired)
)

(define-read-only (get-total-co2-offset)
  (var-get total-co2-offset)
)