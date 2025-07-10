(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_INVALID_STATUS (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_INSUFFICIENT_FUNDS (err u105))
(define-constant ERR_MILESTONE_NOT_FOUND (err u106))
(define-constant ERR_MILESTONE_ALREADY_APPROVED (err u107))
(define-constant ERR_MILESTONE_ALREADY_REJECTED (err u108))
(define-constant ERR_INVALID_MILESTONE_STATUS (err u109))
(define-constant ERR_MILESTONE_DEADLINE_PASSED (err u110))
(define-constant ERR_CAMPAIGN_NOT_FOUND (err u111))
(define-constant ERR_CAMPAIGN_EXPIRED (err u112))
(define-constant ERR_CAMPAIGN_FULLY_MATCHED (err u113))
(define-constant ERR_INVALID_MATCH_RATIO (err u114))
(define-constant ERR_CAMPAIGN_NOT_ACTIVE (err u115))
(define-constant ERR_INSUFFICIENT_MATCHING_FUNDS (err u116))
(define-constant ERR_CAMPAIGN_ALREADY_FINALIZED (err u117))

(define-data-var next-donation-id uint u1)
(define-data-var next-shipment-id uint u1)
(define-data-var next-organization-id uint u1)
(define-data-var next-milestone-project-id uint u1)
(define-data-var next-milestone-id uint u1)
(define-data-var next-matching-campaign-id uint u1)
(define-data-var next-match-contribution-id uint u1)

(define-map donations
  { donation-id: uint }
  {
    donor: principal,
    amount: uint,
    recipient-org: uint,
    purpose: (string-ascii 100),
    timestamp: uint,
    status: (string-ascii 20)
  }
)

(define-map shipments
  { shipment-id: uint }
  {
    donation-id: uint,
    carrier: principal,
    origin: (string-ascii 50),
    destination: (string-ascii 50),
    items: (string-ascii 200),
    status: (string-ascii 20),
    created-at: uint,
    delivered-at: (optional uint)
  }
)

(define-map organizations
  { org-id: uint }
  {
    name: (string-ascii 100),
    wallet: principal,
    location: (string-ascii 100),
    verified: bool,
    total-received: uint
  }
)

(define-map organization-by-wallet
  { wallet: principal }
  { org-id: uint }
)

(define-map authorized-carriers
  { carrier: principal }
  { authorized: bool }
)

(define-map milestone-projects
  { project-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 300),
    donor: principal,
    recipient-org: uint,
    total-amount: uint,
    total-milestones: uint,
    completed-milestones: uint,
    created-at: uint,
    status: (string-ascii 20)
  }
)

(define-map milestones
  { milestone-id: uint }
  {
    project-id: uint,
    title: (string-ascii 100),
    description: (string-ascii 300),
    amount: uint,
    deadline: uint,
    status: (string-ascii 20),
    created-at: uint,
    submitted-at: (optional uint),
    approved-at: (optional uint),
    evidence: (optional (string-ascii 500))
  }
)

(define-map milestone-evidence
  { project-id: uint, milestone-number: uint }
  {
    submitted-by: principal,
    evidence-text: (string-ascii 500),
    submitted-at: uint,
    status: (string-ascii 20)
  }
)

(define-map matching-campaigns
  { campaign-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 300),
    creator: principal,
    recipient-org: uint,
    target-amount: uint,
    match-ratio: uint,
    max-matching-funds: uint,
    current-donations: uint,
    current-matches: uint,
    expires-at: uint,
    created-at: uint,
    status: (string-ascii 20),
    finalized: bool
  }
)

(define-map match-contributions
  { contribution-id: uint }
  {
    campaign-id: uint,
    contributor: principal,
    amount: uint,
    match-amount: uint,
    contributed-at: uint,
    matched: bool
  }
)

(define-map campaign-backers
  { campaign-id: uint, backer: principal }
  {
    total-contributed: uint,
    total-matched: uint,
    contributions-count: uint
  }
)

(define-public (register-organization (name (string-ascii 100)) (location (string-ascii 100)))
  (let
    (
      (org-id (var-get next-organization-id))
      (existing-org (map-get? organization-by-wallet { wallet: tx-sender }))
    )
    (asserts! (is-none existing-org) ERR_ALREADY_EXISTS)
    (map-set organizations
      { org-id: org-id }
      {
        name: name,
        wallet: tx-sender,
        location: location,
        verified: false,
        total-received: u0
      }
    )
    (map-set organization-by-wallet
      { wallet: tx-sender }
      { org-id: org-id }
    )
    (var-set next-organization-id (+ org-id u1))
    (ok org-id)
  )
)

(define-public (verify-organization (org-id uint))
  (let
    (
      (org-data (unwrap! (map-get? organizations { org-id: org-id }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set organizations
      { org-id: org-id }
      (merge org-data { verified: true })
    )
    (ok true)
  )
)

(define-public (authorize-carrier (carrier principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-carriers
      { carrier: carrier }
      { authorized: true }
    )
    (ok true)
  )
)

(define-public (make-donation (recipient-org-id uint) (purpose (string-ascii 100)))
  (let
    (
      (donation-id (var-get next-donation-id))
      (amount (stx-get-balance tx-sender))
      (org-data (unwrap! (map-get? organizations { org-id: recipient-org-id }) ERR_NOT_FOUND))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (get verified org-data) ERR_UNAUTHORIZED)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set donations
      { donation-id: donation-id }
      {
        donor: tx-sender,
        amount: amount,
        recipient-org: recipient-org-id,
        purpose: purpose,
        timestamp: stacks-block-height,
        status: "pending"
      }
    )
    (var-set next-donation-id (+ donation-id u1))
    (ok donation-id)
  )
)

(define-public (create-shipment (donation-id uint) (origin (string-ascii 50)) (destination (string-ascii 50)) (items (string-ascii 200)))
  (let
    (
      (shipment-id (var-get next-shipment-id))
      (donation-data (unwrap! (map-get? donations { donation-id: donation-id }) ERR_NOT_FOUND))
      (org-lookup (unwrap! (map-get? organization-by-wallet { wallet: tx-sender }) ERR_UNAUTHORIZED))
      (org-id (get org-id org-lookup))
    )
    (asserts! (is-eq (get recipient-org donation-data) org-id) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status donation-data) "pending") ERR_INVALID_STATUS)
    (map-set shipments
      { shipment-id: shipment-id }
      {
        donation-id: donation-id,
        carrier: tx-sender,
        origin: origin,
        destination: destination,
        items: items,
        status: "in-transit",
        created-at: stacks-block-height,
        delivered-at: none
      }
    )
    (map-set donations
      { donation-id: donation-id }
      (merge donation-data { status: "shipped" })
    )
    (var-set next-shipment-id (+ shipment-id u1))
    (ok shipment-id)
  )
)

(define-public (update-shipment-status (shipment-id uint) (new-status (string-ascii 20)))
  (let
    (
      (shipment-data (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR_NOT_FOUND))
      (carrier-auth (default-to { authorized: false } (map-get? authorized-carriers { carrier: tx-sender })))
    )
    (asserts! (or (is-eq tx-sender (get carrier shipment-data)) (get authorized carrier-auth)) ERR_UNAUTHORIZED)
    (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment-data { status: new-status })
    )
    (ok true)
  )
)

(define-public (confirm-delivery (shipment-id uint))
  (let
    (
      (shipment-data (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR_NOT_FOUND))
      (donation-data (unwrap! (map-get? donations { donation-id: (get donation-id shipment-data) }) ERR_NOT_FOUND))
      (org-data (unwrap! (map-get? organizations { org-id: (get recipient-org donation-data) }) ERR_NOT_FOUND))
      (carrier-auth (default-to { authorized: false } (map-get? authorized-carriers { carrier: tx-sender })))
    )
    (asserts! (or (is-eq tx-sender (get carrier shipment-data)) (get authorized carrier-auth)) ERR_UNAUTHORIZED)
    (try! (as-contract (stx-transfer? (get amount donation-data) tx-sender (get wallet org-data))))
    (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment-data { 
        status: "delivered",
        delivered-at: (some stacks-block-height)
      })
    )
    (map-set donations
      { donation-id: (get donation-id shipment-data) }
      (merge donation-data { status: "delivered" })
    )
    (map-set organizations
      { org-id: (get recipient-org donation-data) }
      (merge org-data { total-received: (+ (get total-received org-data) (get amount donation-data)) })
    )
    (ok true)
  )
)

(define-read-only (get-donation (donation-id uint))
  (map-get? donations { donation-id: donation-id })
)

(define-read-only (get-shipment (shipment-id uint))
  (map-get? shipments { shipment-id: shipment-id })
)

(define-read-only (get-organization (org-id uint))
  (map-get? organizations { org-id: org-id })
)

(define-read-only (get-organization-by-wallet (wallet principal))
  (match (map-get? organization-by-wallet { wallet: wallet })
    org-lookup (map-get? organizations { org-id: (get org-id org-lookup) })
    none
  )
)

(define-read-only (is-carrier-authorized (carrier principal))
  (default-to false (get authorized (map-get? authorized-carriers { carrier: carrier })))
)

(define-read-only (get-next-donation-id)
  (var-get next-donation-id)
)

(define-read-only (get-next-shipment-id)
  (var-get next-shipment-id)
)

(define-read-only (get-next-organization-id)
  (var-get next-organization-id)
)

(define-public (create-milestone-project (title (string-ascii 100)) (description (string-ascii 300)) (recipient-org-id uint) (total-amount uint) (milestone-count uint))
  (let
    (
      (project-id (var-get next-milestone-project-id))
      (org-data (unwrap! (map-get? organizations { org-id: recipient-org-id }) ERR_NOT_FOUND))
    )
    (asserts! (> total-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> milestone-count u0) ERR_INVALID_AMOUNT)
    (asserts! (get verified org-data) ERR_UNAUTHORIZED)
    (asserts! (>= (stx-get-balance tx-sender) total-amount) ERR_INSUFFICIENT_FUNDS)
    (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
    (map-set milestone-projects
      { project-id: project-id }
      {
        title: title,
        description: description,
        donor: tx-sender,
        recipient-org: recipient-org-id,
        total-amount: total-amount,
        total-milestones: milestone-count,
        completed-milestones: u0,
        created-at: stacks-block-height,
        status: "active"
      }
    )
    (var-set next-milestone-project-id (+ project-id u1))
    (ok project-id)
  )
)

(define-public (create-milestone (project-id uint) (title (string-ascii 100)) (description (string-ascii 300)) (amount uint) (deadline uint))
  (let
    (
      (milestone-id (var-get next-milestone-id))
      (project-data (unwrap! (map-get? milestone-projects { project-id: project-id }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get donor project-data)) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> deadline stacks-block-height) ERR_MILESTONE_DEADLINE_PASSED)
    (asserts! (is-eq (get status project-data) "active") ERR_INVALID_STATUS)
    (map-set milestones
      { milestone-id: milestone-id }
      {
        project-id: project-id,
        title: title,
        description: description,
        amount: amount,
        deadline: deadline,
        status: "pending",
        created-at: stacks-block-height,
        submitted-at: none,
        approved-at: none,
        evidence: none
      }
    )
    (var-set next-milestone-id (+ milestone-id u1))
    (ok milestone-id)
  )
)

(define-public (submit-milestone-evidence (milestone-id uint) (evidence-text (string-ascii 500)))
  (let
    (
      (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
      (project-data (unwrap! (map-get? milestone-projects { project-id: (get project-id milestone-data) }) ERR_NOT_FOUND))
      (org-lookup (unwrap! (map-get? organization-by-wallet { wallet: tx-sender }) ERR_UNAUTHORIZED))
      (org-id (get org-id org-lookup))
    )
    (asserts! (is-eq (get recipient-org project-data) org-id) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status milestone-data) "pending") ERR_INVALID_MILESTONE_STATUS)
    (asserts! (< stacks-block-height (get deadline milestone-data)) ERR_MILESTONE_DEADLINE_PASSED)
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone-data { 
        status: "submitted",
        submitted-at: (some stacks-block-height),
        evidence: (some evidence-text)
      })
    )
    (ok true)
  )
)

(define-public (approve-milestone (milestone-id uint))
  (let
    (
      (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
      (project-data (unwrap! (map-get? milestone-projects { project-id: (get project-id milestone-data) }) ERR_NOT_FOUND))
      (org-data (unwrap! (map-get? organizations { org-id: (get recipient-org project-data) }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get donor project-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status milestone-data) "submitted") ERR_INVALID_MILESTONE_STATUS)
    (try! (as-contract (stx-transfer? (get amount milestone-data) tx-sender (get wallet org-data))))
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone-data { 
        status: "approved",
        approved-at: (some stacks-block-height)
      })
    )
    (map-set milestone-projects
      { project-id: (get project-id milestone-data) }
      (merge project-data { 
        completed-milestones: (+ (get completed-milestones project-data) u1)
      })
    )
    (map-set organizations
      { org-id: (get recipient-org project-data) }
      (merge org-data { total-received: (+ (get total-received org-data) (get amount milestone-data)) })
    )
    (ok true)
  )
)

(define-public (reject-milestone (milestone-id uint) (reason (string-ascii 200)))
  (let
    (
      (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
      (project-data (unwrap! (map-get? milestone-projects { project-id: (get project-id milestone-data) }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get donor project-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status milestone-data) "submitted") ERR_INVALID_MILESTONE_STATUS)
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone-data { 
        status: "rejected",
        evidence: (some reason)
      })
    )
    (ok true)
  )
)

(define-public (cancel-milestone-project (project-id uint))
  (let
    (
      (project-data (unwrap! (map-get? milestone-projects { project-id: project-id }) ERR_NOT_FOUND))
      (refund-amount (- (get total-amount project-data) (* (get completed-milestones project-data) (/ (get total-amount project-data) (get total-milestones project-data)))))
    )
    (asserts! (is-eq tx-sender (get donor project-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status project-data) "active") ERR_INVALID_STATUS)
    (try! (as-contract (stx-transfer? refund-amount tx-sender (get donor project-data))))
    (map-set milestone-projects
      { project-id: project-id }
      (merge project-data { status: "cancelled" })
    )
    (ok refund-amount)
  )
)

(define-public (complete-milestone-project (project-id uint))
  (let
    (
      (project-data (unwrap! (map-get? milestone-projects { project-id: project-id }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get donor project-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get completed-milestones project-data) (get total-milestones project-data)) ERR_INVALID_STATUS)
    (map-set milestone-projects
      { project-id: project-id }
      (merge project-data { status: "completed" })
    )
    (ok true)
  )
)

(define-read-only (get-milestone-project (project-id uint))
  (map-get? milestone-projects { project-id: project-id })
)

(define-read-only (get-milestone (milestone-id uint))
  (map-get? milestones { milestone-id: milestone-id })
)

(define-read-only (get-milestone-evidence (project-id uint) (milestone-number uint))
  (map-get? milestone-evidence { project-id: project-id, milestone-number: milestone-number })
)

(define-read-only (get-project-progress (project-id uint))
  (match (map-get? milestone-projects { project-id: project-id })
    project-data (ok {
      completed: (get completed-milestones project-data),
      total: (get total-milestones project-data),
      percentage: (/ (* (get completed-milestones project-data) u100) (get total-milestones project-data))
    })
    ERR_NOT_FOUND
  )
)

(define-read-only (get-next-milestone-project-id)
  (var-get next-milestone-project-id)
)

(define-read-only (get-next-milestone-id)
  (var-get next-milestone-id)
)

(define-public (create-matching-campaign (title (string-ascii 100)) (description (string-ascii 300)) (recipient-org-id uint) (target-amount uint) (match-ratio uint) (max-matching-funds uint) (duration-blocks uint))
  (let
    (
      (campaign-id (var-get next-matching-campaign-id))
      (org-data (unwrap! (map-get? organizations { org-id: recipient-org-id }) ERR_NOT_FOUND))
      (expires-at (+ stacks-block-height duration-blocks))
    )
    (asserts! (> target-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> max-matching-funds u0) ERR_INVALID_AMOUNT)
    (asserts! (and (> match-ratio u0) (<= match-ratio u200)) ERR_INVALID_MATCH_RATIO)
    (asserts! (> duration-blocks u0) ERR_INVALID_AMOUNT)
    (asserts! (get verified org-data) ERR_UNAUTHORIZED)
    (asserts! (>= (stx-get-balance tx-sender) max-matching-funds) ERR_INSUFFICIENT_MATCHING_FUNDS)
    (try! (stx-transfer? max-matching-funds tx-sender (as-contract tx-sender)))
    (map-set matching-campaigns
      { campaign-id: campaign-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        recipient-org: recipient-org-id,
        target-amount: target-amount,
        match-ratio: match-ratio,
        max-matching-funds: max-matching-funds,
        current-donations: u0,
        current-matches: u0,
        expires-at: expires-at,
        created-at: stacks-block-height,
        status: "active",
        finalized: false
      }
    )
    (var-set next-matching-campaign-id (+ campaign-id u1))
    (ok campaign-id)
  )
)

(define-public (contribute-to-campaign (campaign-id uint) (amount uint))
  (let
    (
      (contribution-id (var-get next-match-contribution-id))
      (campaign-data (unwrap! (map-get? matching-campaigns { campaign-id: campaign-id }) ERR_CAMPAIGN_NOT_FOUND))
      (match-amount (/ (* amount (get match-ratio campaign-data)) u100))
      (remaining-match-funds (- (get max-matching-funds campaign-data) (get current-matches campaign-data)))
      (actual-match-amount (if (> match-amount remaining-match-funds) remaining-match-funds match-amount))
      (backer-data (default-to { total-contributed: u0, total-matched: u0, contributions-count: u0 } 
                                (map-get? campaign-backers { campaign-id: campaign-id, backer: tx-sender })))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (is-eq (get status campaign-data) "active") ERR_CAMPAIGN_NOT_ACTIVE)
    (asserts! (< stacks-block-height (get expires-at campaign-data)) ERR_CAMPAIGN_EXPIRED)
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_FUNDS)
    (asserts! (> actual-match-amount u0) ERR_CAMPAIGN_FULLY_MATCHED)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set match-contributions
      { contribution-id: contribution-id }
      {
        campaign-id: campaign-id,
        contributor: tx-sender,
        amount: amount,
        match-amount: actual-match-amount,
        contributed-at: stacks-block-height,
        matched: false
      }
    )
    (map-set campaign-backers
      { campaign-id: campaign-id, backer: tx-sender }
      {
        total-contributed: (+ (get total-contributed backer-data) amount),
        total-matched: (+ (get total-matched backer-data) actual-match-amount),
        contributions-count: (+ (get contributions-count backer-data) u1)
      }
    )
    (map-set matching-campaigns
      { campaign-id: campaign-id }
      (merge campaign-data { 
        current-donations: (+ (get current-donations campaign-data) amount),
        current-matches: (+ (get current-matches campaign-data) actual-match-amount)
      })
    )
    (var-set next-match-contribution-id (+ contribution-id u1))
    (ok contribution-id)
  )
)

(define-public (finalize-campaign (campaign-id uint))
  (let
    (
      (campaign-data (unwrap! (map-get? matching-campaigns { campaign-id: campaign-id }) ERR_CAMPAIGN_NOT_FOUND))
      (org-data (unwrap! (map-get? organizations { org-id: (get recipient-org campaign-data) }) ERR_NOT_FOUND))
      (total-transfer (+ (get current-donations campaign-data) (get current-matches campaign-data)))
      (unused-match-funds (- (get max-matching-funds campaign-data) (get current-matches campaign-data)))
    )
    (asserts! (is-eq tx-sender (get creator campaign-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status campaign-data) "active") ERR_CAMPAIGN_NOT_ACTIVE)
    (asserts! (not (get finalized campaign-data)) ERR_CAMPAIGN_ALREADY_FINALIZED)
    (asserts! (or (>= stacks-block-height (get expires-at campaign-data)) 
                  (>= (get current-donations campaign-data) (get target-amount campaign-data))) ERR_CAMPAIGN_NOT_ACTIVE)
    (try! (as-contract (stx-transfer? total-transfer tx-sender (get wallet org-data))))
    (if (> unused-match-funds u0)
      (try! (as-contract (stx-transfer? unused-match-funds tx-sender (get creator campaign-data))))
      true
    )
    (map-set matching-campaigns
      { campaign-id: campaign-id }
      (merge campaign-data { 
        status: "completed",
        finalized: true
      })
    )
    (map-set organizations
      { org-id: (get recipient-org campaign-data) }
      (merge org-data { 
        total-received: (+ (get total-received org-data) total-transfer)
      })
    )
    (ok total-transfer)
  )
)

(define-public (cancel-campaign (campaign-id uint))
  (let
    (
      (campaign-data (unwrap! (map-get? matching-campaigns { campaign-id: campaign-id }) ERR_CAMPAIGN_NOT_FOUND))
      (refund-amount (+ (get current-donations campaign-data) (get max-matching-funds campaign-data)))
    )
    (asserts! (is-eq tx-sender (get creator campaign-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status campaign-data) "active") ERR_CAMPAIGN_NOT_ACTIVE)
    (asserts! (not (get finalized campaign-data)) ERR_CAMPAIGN_ALREADY_FINALIZED)
    (try! (as-contract (stx-transfer? refund-amount tx-sender (get creator campaign-data))))
    (map-set matching-campaigns
      { campaign-id: campaign-id }
      (merge campaign-data { 
        status: "cancelled",
        finalized: true
      })
    )
    (ok refund-amount)
  )
)

(define-public (extend-campaign (campaign-id uint) (additional-blocks uint))
  (let
    (
      (campaign-data (unwrap! (map-get? matching-campaigns { campaign-id: campaign-id }) ERR_CAMPAIGN_NOT_FOUND))
      (new-expires-at (+ (get expires-at campaign-data) additional-blocks))
    )
    (asserts! (is-eq tx-sender (get creator campaign-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status campaign-data) "active") ERR_CAMPAIGN_NOT_ACTIVE)
    (asserts! (> additional-blocks u0) ERR_INVALID_AMOUNT)
    (asserts! (< stacks-block-height (get expires-at campaign-data)) ERR_CAMPAIGN_EXPIRED)
    (map-set matching-campaigns
      { campaign-id: campaign-id }
      (merge campaign-data { expires-at: new-expires-at })
    )
    (ok new-expires-at)
  )
)

(define-read-only (get-matching-campaign (campaign-id uint))
  (map-get? matching-campaigns { campaign-id: campaign-id })
)

(define-read-only (get-match-contribution (contribution-id uint))
  (map-get? match-contributions { contribution-id: contribution-id })
)

(define-read-only (get-campaign-backer (campaign-id uint) (backer principal))
  (map-get? campaign-backers { campaign-id: campaign-id, backer: backer })
)

(define-read-only (get-campaign-stats (campaign-id uint))
  (match (map-get? matching-campaigns { campaign-id: campaign-id })
    campaign-data (ok {
      progress-percentage: (if (> (get target-amount campaign-data) u0)
                            (/ (* (get current-donations campaign-data) u100) (get target-amount campaign-data))
                            u0),
      match-percentage: (if (> (get max-matching-funds campaign-data) u0)
                         (/ (* (get current-matches campaign-data) u100) (get max-matching-funds campaign-data))
                         u0),
      total-impact: (+ (get current-donations campaign-data) (get current-matches campaign-data)),
      blocks-remaining: (if (> (get expires-at campaign-data) stacks-block-height)
                         (- (get expires-at campaign-data) stacks-block-height)
                         u0),
      is-expired: (>= stacks-block-height (get expires-at campaign-data))
    })
    ERR_CAMPAIGN_NOT_FOUND
  )
)

(define-read-only (get-next-matching-campaign-id)
  (var-get next-matching-campaign-id)
)

(define-read-only (get-next-match-contribution-id)
  (var-get next-match-contribution-id)
)