(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_INVALID_STATUS (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_INSUFFICIENT_FUNDS (err u105))

(define-data-var next-donation-id uint u1)
(define-data-var next-shipment-id uint u1)
(define-data-var next-organization-id uint u1)

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