(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_NOT_FOUND (err u201))
(define-constant ERR_INVALID_RATING (err u202))
(define-constant ERR_ALREADY_VERIFIED (err u203))
(define-constant ERR_REPORT_NOT_FOUND (err u204))
(define-constant ERR_INSUFFICIENT_STAKE (err u205))
(define-constant ERR_VERIFICATION_CLOSED (err u206))
(define-constant ERR_INVALID_CATEGORY (err u207))
(define-constant ERR_ALREADY_VOTED (err u208))
(define-constant ERR_INVALID_EVIDENCE (err u209))

;; Minimum stake required to become a verifier (1000 microSTX)
(define-constant MIN_VERIFIER_STAKE u1000000)
;; Reward for successful verification (100 microSTX)
(define-constant VERIFICATION_REWARD u100000)

(define-data-var next-impact-report-id uint u1)
(define-data-var next-verification-id uint u1)
(define-data-var total-verified-reports uint u0)

;; Impact reports submitted by organizations
(define-map impact-reports
  { report-id: uint }
  {
    org-id: uint,
    title: (string-ascii 150),
    description: (string-ascii 500),
    category: (string-ascii 50),
    beneficiaries-count: uint,
    funds-used: uint,
    evidence-urls: (list 3 (string-ascii 200)),
    submitted-at: uint,
    verification-deadline: uint,
    total-verifications: uint,
    positive-verifications: uint,
    status: (string-ascii 20),
    final-score: uint
  }
)

;; Community verifications for impact reports
(define-map impact-verifications
  { verification-id: uint }
  {
    report-id: uint,
    verifier: principal,
    rating: uint,
    confidence: uint,
    evidence-quality: uint,
    comments: (string-ascii 300),
    submitted-at: uint,
    reward-claimed: bool
  }
)

;; Verifier registry with staking and reputation
(define-map community-verifiers
  { verifier: principal }
  {
    stake-amount: uint,
    reputation-score: uint,
    total-verifications: uint,
    successful-verifications: uint,
    registered-at: uint,
    active: bool
  }
)

;; Track which verifiers have voted on which reports
(define-map verifier-votes
  { report-id: uint, verifier: principal }
  { voted: bool }
)

;; Organization reputation based on verified impact
(define-map org-reputation
  { org-id: uint }
  {
    total-reports: uint,
    verified-reports: uint,
    average-impact-score: uint,
    total-beneficiaries: uint,
    reputation-tier: (string-ascii 20)
  }
)

;; Impact categories for standardized reporting
(define-map impact-categories
  { category: (string-ascii 50) }
  {
    active: bool,
    total-reports: uint,
    average-score: uint
  }
)

;; Register as a community verifier with stake
(define-public (register-verifier (stake-amount uint))
  (let
    (
      (existing-verifier (map-get? community-verifiers { verifier: tx-sender }))
    )
    (asserts! (is-none existing-verifier) ERR_ALREADY_VERIFIED)
    (asserts! (>= stake-amount MIN_VERIFIER_STAKE) ERR_INSUFFICIENT_STAKE)
    (asserts! (>= (stx-get-balance tx-sender) stake-amount) ERR_INSUFFICIENT_STAKE)
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    (map-set community-verifiers
      { verifier: tx-sender }
      {
        stake-amount: stake-amount,
        reputation-score: u100,
        total-verifications: u0,
        successful-verifications: u0,
        registered-at: stacks-block-height,
        active: true
      }
    )
    (ok true)
  )
)

;; Submit impact report for community verification
(define-public (submit-impact-report (org-id uint) (title (string-ascii 150)) (description (string-ascii 500)) (category (string-ascii 50)) (beneficiaries-count uint) (funds-used uint) (evidence-urls (list 3 (string-ascii 200))))
  (let
    (
      (report-id (var-get next-impact-report-id))
      (verification-deadline (+ stacks-block-height u144)) ;; ~24 hours in blocks
    )
    (asserts! (> beneficiaries-count u0) ERR_INVALID_RATING)
    (asserts! (> funds-used u0) ERR_INVALID_RATING)
    (asserts! (> (len evidence-urls) u0) ERR_INVALID_EVIDENCE)
    (map-set impact-reports
      { report-id: report-id }
      {
        org-id: org-id,
        title: title,
        description: description,
        category: category,
        beneficiaries-count: beneficiaries-count,
        funds-used: funds-used,
        evidence-urls: evidence-urls,
        submitted-at: stacks-block-height,
        verification-deadline: verification-deadline,
        total-verifications: u0,
        positive-verifications: u0,
        status: "pending",
        final-score: u0
      }
    )
    (let
      (
        (category-data (default-to { active: true, total-reports: u0, average-score: u0 } 
                                   (map-get? impact-categories { category: category })))
      )
      (map-set impact-categories
        { category: category }
        (merge category-data { 
          total-reports: (+ (get total-reports category-data) u1)
        })
      )
    )
    (var-set next-impact-report-id (+ report-id u1))
    (ok report-id)
  )
)

;; Verify an impact report (rating: 1-100, confidence: 1-100, evidence-quality: 1-100)
(define-public (verify-impact-report (report-id uint) (rating uint) (confidence uint) (evidence-quality uint) (comments (string-ascii 300)))
  (let
    (
      (verification-id (var-get next-verification-id))
      (report-data (unwrap! (map-get? impact-reports { report-id: report-id }) ERR_REPORT_NOT_FOUND))
      (verifier-data (unwrap! (map-get? community-verifiers { verifier: tx-sender }) ERR_UNAUTHORIZED))
      (existing-vote (map-get? verifier-votes { report-id: report-id, verifier: tx-sender }))
    )
    (asserts! (get active verifier-data) ERR_UNAUTHORIZED)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    (asserts! (is-eq (get status report-data) "pending") ERR_VERIFICATION_CLOSED)
    (asserts! (< stacks-block-height (get verification-deadline report-data)) ERR_VERIFICATION_CLOSED)
    (asserts! (and (>= rating u1) (<= rating u100)) ERR_INVALID_RATING)
    (asserts! (and (>= confidence u1) (<= confidence u100)) ERR_INVALID_RATING)
    (asserts! (and (>= evidence-quality u1) (<= evidence-quality u100)) ERR_INVALID_RATING)
    (map-set impact-verifications
      { verification-id: verification-id }
      {
        report-id: report-id,
        verifier: tx-sender,
        rating: rating,
        confidence: confidence,
        evidence-quality: evidence-quality,
        comments: comments,
        submitted-at: stacks-block-height,
        reward-claimed: false
      }
    )
    (map-set verifier-votes
      { report-id: report-id, verifier: tx-sender }
      { voted: true }
    )
    (let
      (
        (new-total-verifications (+ (get total-verifications report-data) u1))
        (new-positive-verifications (+ (get positive-verifications report-data) (if (>= rating u70) u1 u0)))
      )
      (map-set impact-reports
        { report-id: report-id }
        (merge report-data {
          total-verifications: new-total-verifications,
          positive-verifications: new-positive-verifications
        })
      )
    )
    (map-set community-verifiers
      { verifier: tx-sender }
      (merge verifier-data {
        total-verifications: (+ (get total-verifications verifier-data) u1)
      })
    )
    (var-set next-verification-id (+ verification-id u1))
    (ok verification-id)
  )
)

;; Finalize impact report and distribute rewards
(define-public (finalize-impact-report (report-id uint))
  (let
    (
      (report-data (unwrap! (map-get? impact-reports { report-id: report-id }) ERR_REPORT_NOT_FOUND))
      (verification-count (get total-verifications report-data))
      (positive-count (get positive-verifications report-data))
      (final-score (if (> verification-count u0) (/ (* positive-count u100) verification-count) u0))
      (org-reputation-data (default-to { total-reports: u0, verified-reports: u0, average-impact-score: u0, total-beneficiaries: u0, reputation-tier: "bronze" } 
                                       (map-get? org-reputation { org-id: (get org-id report-data) })))
    )
    (asserts! (>= stacks-block-height (get verification-deadline report-data)) ERR_VERIFICATION_CLOSED)
    (asserts! (is-eq (get status report-data) "pending") ERR_VERIFICATION_CLOSED)
    (asserts! (>= verification-count u3) ERR_INSUFFICIENT_STAKE)
    (map-set impact-reports
      { report-id: report-id }
      (merge report-data {
        status: "verified",
        final-score: final-score
      })
    )
    (let
      (
        (new-total-reports (+ (get total-reports org-reputation-data) u1))
        (new-verified-reports (+ (get verified-reports org-reputation-data) u1))
        (new-total-beneficiaries (+ (get total-beneficiaries org-reputation-data) (get beneficiaries-count report-data)))
        (weighted-score (/ (+ (* (get average-impact-score org-reputation-data) (get verified-reports org-reputation-data)) final-score) new-verified-reports))
        (new-tier (if (>= weighted-score u90) "platinum" 
                    (if (>= weighted-score u75) "gold"
                      (if (>= weighted-score u60) "silver" "bronze"))))
      )
      (map-set org-reputation
        { org-id: (get org-id report-data) }
        {
          total-reports: new-total-reports,
          verified-reports: new-verified-reports,
          average-impact-score: weighted-score,
          total-beneficiaries: new-total-beneficiaries,
          reputation-tier: new-tier
        }
      )
    )
    (var-set total-verified-reports (+ (var-get total-verified-reports) u1))
    (ok final-score)
  )
)

;; Claim verification reward for successful verifiers
(define-public (claim-verification-reward (verification-id uint))
  (let
    (
      (verification-data (unwrap! (map-get? impact-verifications { verification-id: verification-id }) ERR_NOT_FOUND))
      (report-data (unwrap! (map-get? impact-reports { report-id: (get report-id verification-data) }) ERR_REPORT_NOT_FOUND))
      (verifier-data (unwrap! (map-get? community-verifiers { verifier: tx-sender }) ERR_UNAUTHORIZED))
    )
    (asserts! (is-eq tx-sender (get verifier verification-data)) ERR_UNAUTHORIZED)
    (asserts! (not (get reward-claimed verification-data)) ERR_ALREADY_VERIFIED)
    (asserts! (is-eq (get status report-data) "verified") ERR_VERIFICATION_CLOSED)
    (asserts! (>= (get final-score report-data) u50) ERR_INVALID_RATING)
    (try! (as-contract (stx-transfer? VERIFICATION_REWARD tx-sender (get verifier verification-data))))
    (map-set impact-verifications
      { verification-id: verification-id }
      (merge verification-data { reward-claimed: true })
    )
    (map-set community-verifiers
      { verifier: tx-sender }
      (merge verifier-data {
        successful-verifications: (+ (get successful-verifications verifier-data) u1),
        reputation-score: (if (>= (+ (get reputation-score verifier-data) u5) u200) u200 (+ (get reputation-score verifier-data) u5))
      })
    )
    (ok true)
  )
)

;; Update verifier stake
(define-public (increase-verifier-stake (additional-amount uint))
  (let
    (
      (verifier-data (unwrap! (map-get? community-verifiers { verifier: tx-sender }) ERR_UNAUTHORIZED))
    )
    (asserts! (> additional-amount u0) ERR_INVALID_RATING)
    (asserts! (>= (stx-get-balance tx-sender) additional-amount) ERR_INSUFFICIENT_STAKE)
    (try! (stx-transfer? additional-amount tx-sender (as-contract tx-sender)))
    (map-set community-verifiers
      { verifier: tx-sender }
      (merge verifier-data {
        stake-amount: (+ (get stake-amount verifier-data) additional-amount)
      })
    )
    (ok true)
  )
)

;; Withdraw verifier stake (requires good reputation)
(define-public (withdraw-verifier-stake (amount uint))
  (let
    (
      (verifier-data (unwrap! (map-get? community-verifiers { verifier: tx-sender }) ERR_UNAUTHORIZED))
      (remaining-stake (- (get stake-amount verifier-data) amount))
    )
    (asserts! (>= (get reputation-score verifier-data) u80) ERR_UNAUTHORIZED)
    (asserts! (>= remaining-stake MIN_VERIFIER_STAKE) ERR_INSUFFICIENT_STAKE)
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (map-set community-verifiers
      { verifier: tx-sender }
      (merge verifier-data {
        stake-amount: remaining-stake
      })
    )
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-impact-report (report-id uint))
  (map-get? impact-reports { report-id: report-id })
)

(define-read-only (get-verification (verification-id uint))
  (map-get? impact-verifications { verification-id: verification-id })
)

(define-read-only (get-verifier-info (verifier principal))
  (map-get? community-verifiers { verifier: verifier })
)

(define-read-only (get-org-reputation (org-id uint))
  (map-get? org-reputation { org-id: org-id })
)

(define-read-only (get-impact-category (category (string-ascii 50)))
  (map-get? impact-categories { category: category })
)

(define-read-only (has-verifier-voted (report-id uint) (verifier principal))
  (default-to false (get voted (map-get? verifier-votes { report-id: report-id, verifier: verifier })))
)

;; Calculate weighted verification score
(define-read-only (get-weighted-report-score (report-id uint))
  (match (map-get? impact-reports { report-id: report-id })
    report-data (ok {
      basic-score: (get final-score report-data),
      verification-count: (get total-verifications report-data),
      confidence-weighted: (if (> (get total-verifications report-data) u0)
                            (/ (* (get final-score report-data) (get total-verifications report-data)) u10)
                            u0),
      is-verified: (is-eq (get status report-data) "verified")
    })
    ERR_REPORT_NOT_FOUND
  )
)

;; Get verifier performance metrics
(define-read-only (get-verifier-metrics (verifier principal))
  (match (map-get? community-verifiers { verifier: verifier })
    verifier-data (ok {
      accuracy-rate: (if (> (get total-verifications verifier-data) u0)
                      (/ (* (get successful-verifications verifier-data) u100) (get total-verifications verifier-data))
                      u0),
      reputation-score: (get reputation-score verifier-data),
      stake-amount: (get stake-amount verifier-data),
      verification-power: (/ (get stake-amount verifier-data) MIN_VERIFIER_STAKE),
      active-status: (get active verifier-data)
    })
    ERR_UNAUTHORIZED
  )
)

;; Get comprehensive impact statistics
(define-read-only (get-impact-overview)
  (ok {
    total-verified-reports: (var-get total-verified-reports),
    next-report-id: (var-get next-impact-report-id),
    next-verification-id: (var-get next-verification-id),
    min-stake-required: MIN_VERIFIER_STAKE,
    verification-reward: VERIFICATION_REWARD
  })
)

(define-read-only (get-next-impact-report-id)
  (var-get next-impact-report-id)
)

(define-read-only (get-next-verification-id)
  (var-get next-verification-id)
)
