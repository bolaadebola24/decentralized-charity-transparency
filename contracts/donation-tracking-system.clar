;; Donation Tracking System Contract
;; Track donations from donors to final recipients, verify fund usage, monitor project progress,
;; prevent fraud, and ensure transparent charitable distribution

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-already-exists (err u105))
(define-constant err-invalid-milestone (err u106))
(define-constant err-funds-released (err u107))

;; Data structures
(define-map charitable-organizations
  { org-id: (string-ascii 64) }
  {
    name: (string-ascii 128),
    description: (string-ascii 512),
    registration-date: uint,
    verification-status: (string-ascii 16),
    total-raised: uint,
    total-projects: uint,
    efficiency-rating: uint,
    contact-info: (string-ascii 256),
    certifications: (list 5 (string-ascii 64)),
    is-active: bool
  }
)

(define-map charitable-projects
  { project-id: (string-ascii 64) }
  {
    org-id: (string-ascii 64),
    title: (string-ascii 128),
    description: (string-ascii 1024),
    target-amount: uint,
    raised-amount: uint,
    start-date: uint,
    end-date: uint,
    category: (string-ascii 32),
    location: (string-ascii 128),
    status: (string-ascii 16),
    milestone-count: uint,
    completed-milestones: uint,
    beneficiary-count: uint
  }
)

(define-map project-milestones
  { project-id: (string-ascii 64), milestone-id: uint }
  {
    title: (string-ascii 128),
    description: (string-ascii 512),
    target-amount: uint,
    allocated-amount: uint,
    completion-date: uint,
    verification-status: (string-ascii 16),
    evidence-hash: (string-ascii 64),
    is-completed: bool,
    funds-released: bool
  }
)

(define-map donations
  { donation-id: (string-ascii 64) }
  {
    donor: principal,
    project-id: (string-ascii 64),
    amount: uint,
    donation-date: uint,
    allocation-preference: (string-ascii 32),
    is-anonymous: bool,
    message: (string-ascii 256),
    tax-receipt-requested: bool,
    tracking-updates: bool
  }
)

(define-map fund-allocations
  { project-id: (string-ascii 64), allocation-id: uint }
  {
    milestone-id: uint,
    amount: uint,
    allocation-date: uint,
    purpose: (string-ascii 128),
    recipient: (string-ascii 128),
    verification-status: (string-ascii 16),
    receipt-hash: (string-ascii 64),
    impact-category: (string-ascii 32)
  }
)

(define-map recipients
  { recipient-id: (string-ascii 64) }
  {
    name: (string-ascii 128),
    location: (string-ascii 128),
    category: (string-ascii 32),
    verification-status: (string-ascii 16),
    total-received: uint,
    project-count: uint,
    consent-given: bool,
    contact-method: (string-ascii 64)
  }
)

(define-map transparency-reports
  { project-id: (string-ascii 64), report-id: uint }
  {
    report-date: uint,
    funds-utilized: uint,
    beneficiaries-served: uint,
    milestones-completed: uint,
    efficiency-metrics: (list 5 uint),
    challenges-faced: (string-ascii 512),
    next-steps: (string-ascii 256),
    verification-status: (string-ascii 16)
  }
)

;; Data variables
(define-data-var org-counter uint u0)
(define-data-var project-counter uint u0)
(define-data-var donation-counter uint u0)
(define-data-var recipient-counter uint u0)
(define-data-var total-platform-donations uint u0)
(define-data-var platform-fee-percentage uint u3) ;; 3% platform fee

;; Private functions
(define-private (is-authorized-org (org-id (string-ascii 64)))
  (let (
    (org-info (map-get? charitable-organizations { org-id: org-id }))
  )
    (match org-info
      organization
      (and 
        (is-eq (get verification-status organization) "verified")
        (get is-active organization)
      )
      false
    )
  )
)

(define-private (generate-org-id (counter uint))
  (concat "ORG-" (int-to-ascii counter))
)

(define-private (generate-project-id (counter uint))
  (concat "PROJ-" (int-to-ascii counter))
)

(define-private (generate-donation-id (counter uint))
  (concat "DON-" (int-to-ascii counter))
)

(define-private (generate-recipient-id (counter uint))
  (concat "REC-" (int-to-ascii counter))
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-percentage)) u100)
)

(define-private (update-org-stats (org-id (string-ascii 64)) (amount uint))
  (let (
    (org-info (unwrap! (map-get? charitable-organizations { org-id: org-id }) (err u0)))
  )
    (map-set charitable-organizations
      { org-id: org-id }
      (merge org-info {
        total-raised: (+ (get total-raised org-info) amount)
      })
    )
    (ok true)
  )
)

;; Public functions

;; Register charitable organization
(define-public (register-organization
    (name (string-ascii 128))
    (description (string-ascii 512))
    (contact-info (string-ascii 256))
    (certifications (list 5 (string-ascii 64)))
  )
  (let (
    (counter (+ (var-get org-counter) u1))
    (org-id (generate-org-id counter))
  )
    (map-set charitable-organizations
      { org-id: org-id }
      {
        name: name,
        description: description,
        registration-date: block-height,
        verification-status: "pending",
        total-raised: u0,
        total-projects: u0,
        efficiency-rating: u50,
        contact-info: contact-info,
        certifications: certifications,
        is-active: true
      }
    )
    (var-set org-counter counter)
    (ok org-id)
  )
)

;; Verify organization (owner only)
(define-public (verify-organization (org-id (string-ascii 64)))
  (let (
    (org-info (unwrap! (map-get? charitable-organizations { org-id: org-id }) err-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set charitable-organizations
      { org-id: org-id }
      (merge org-info {
        verification-status: "verified"
      })
    )
    (ok true)
  )
)

;; Create charitable project
(define-public (create-project
    (org-id (string-ascii 64))
    (title (string-ascii 128))
    (description (string-ascii 1024))
    (target-amount uint)
    (end-date uint)
    (category (string-ascii 32))
    (location (string-ascii 128))
    (beneficiary-count uint)
  )
  (let (
    (counter (+ (var-get project-counter) u1))
    (project-id (generate-project-id counter))
    (org-info (unwrap! (map-get? charitable-organizations { org-id: org-id }) err-not-found))
  )
    (asserts! (is-authorized-org org-id) err-unauthorized)
    (map-set charitable-projects
      { project-id: project-id }
      {
        org-id: org-id,
        title: title,
        description: description,
        target-amount: target-amount,
        raised-amount: u0,
        start-date: block-height,
        end-date: end-date,
        category: category,
        location: location,
        status: "active",
        milestone-count: u0,
        completed-milestones: u0,
        beneficiary-count: beneficiary-count
      }
    )
    
    ;; Update organization stats
    (map-set charitable-organizations
      { org-id: org-id }
      (merge org-info {
        total-projects: (+ (get total-projects org-info) u1)
      })
    )
    
    (var-set project-counter counter)
    (ok project-id)
  )
)

;; Make donation
(define-public (make-donation
    (project-id (string-ascii 64))
    (amount uint)
    (allocation-preference (string-ascii 32))
    (is-anonymous bool)
    (message (string-ascii 256))
    (tax-receipt-requested bool)
  )
  (let (
    (counter (+ (var-get donation-counter) u1))
    (donation-id (generate-donation-id counter))
    (project-info (unwrap! (map-get? charitable-projects { project-id: project-id }) err-not-found))
    (platform-fee (calculate-platform-fee amount))
    (net-donation (- amount platform-fee))
  )
    (asserts! (is-eq (get status project-info) "active") err-invalid-status)
    (asserts! (> amount u0) err-insufficient-funds)
    
    ;; Record donation
    (map-set donations
      { donation-id: donation-id }
      {
        donor: tx-sender,
        project-id: project-id,
        amount: net-donation,
        donation-date: block-height,
        allocation-preference: allocation-preference,
        is-anonymous: is-anonymous,
        message: message,
        tax-receipt-requested: tax-receipt-requested,
        tracking-updates: true
      }
    )
    
    ;; Update project funding
    (map-set charitable-projects
      { project-id: project-id }
      (merge project-info {
        raised-amount: (+ (get raised-amount project-info) net-donation)
      })
    )
    
    ;; Update organization stats
    (try! (update-org-stats (get org-id project-info) net-donation))
    
    (var-set donation-counter counter)
    (var-set total-platform-donations (+ (var-get total-platform-donations) net-donation))
    (ok donation-id)
  )
)

;; Create project milestone
(define-public (create-milestone
    (project-id (string-ascii 64))
    (title (string-ascii 128))
    (description (string-ascii 512))
    (target-amount uint)
  )
  (let (
    (project-info (unwrap! (map-get? charitable-projects { project-id: project-id }) err-not-found))
    (milestone-id (+ (get milestone-count project-info) u1))
  )
    (asserts! (is-authorized-org (get org-id project-info)) err-unauthorized)
    
    (map-set project-milestones
      { project-id: project-id, milestone-id: milestone-id }
      {
        title: title,
        description: description,
        target-amount: target-amount,
        allocated-amount: u0,
        completion-date: u0,
        verification-status: "pending",
        evidence-hash: "",
        is-completed: false,
        funds-released: false
      }
    )
    
    ;; Update project milestone count
    (map-set charitable-projects
      { project-id: project-id }
      (merge project-info {
        milestone-count: milestone-id
      })
    )
    
    (ok milestone-id)
  )
)

;; Complete milestone
(define-public (complete-milestone
    (project-id (string-ascii 64))
    (milestone-id uint)
    (evidence-hash (string-ascii 64))
  )
  (let (
    (project-info (unwrap! (map-get? charitable-projects { project-id: project-id }) err-not-found))
    (milestone-info (unwrap! (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id }) err-not-found))
  )
    (asserts! (is-authorized-org (get org-id project-info)) err-unauthorized)
    (asserts! (not (get is-completed milestone-info)) err-invalid-status)
    
    (map-set project-milestones
      { project-id: project-id, milestone-id: milestone-id }
      (merge milestone-info {
        completion-date: block-height,
        verification-status: "completed",
        evidence-hash: evidence-hash,
        is-completed: true
      })
    )
    
    ;; Update project completed milestones
    (map-set charitable-projects
      { project-id: project-id }
      (merge project-info {
        completed-milestones: (+ (get completed-milestones project-info) u1)
      })
    )
    
    (ok true)
  )
)

;; Release funds for milestone
(define-public (release-milestone-funds
    (project-id (string-ascii 64))
    (milestone-id uint)
    (amount uint)
  )
  (let (
    (project-info (unwrap! (map-get? charitable-projects { project-id: project-id }) err-not-found))
    (milestone-info (unwrap! (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id }) err-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (get is-completed milestone-info) err-invalid-milestone)
    (asserts! (not (get funds-released milestone-info)) err-funds-released)
    (asserts! (<= amount (get raised-amount project-info)) err-insufficient-funds)
    
    (map-set project-milestones
      { project-id: project-id, milestone-id: milestone-id }
      (merge milestone-info {
        allocated-amount: amount,
        funds-released: true
      })
    )
    
    (ok amount)
  )
)

;; Register recipient
(define-public (register-recipient
    (name (string-ascii 128))
    (location (string-ascii 128))
    (category (string-ascii 32))
    (contact-method (string-ascii 64))
  )
  (let (
    (counter (+ (var-get recipient-counter) u1))
    (recipient-id (generate-recipient-id counter))
  )
    (map-set recipients
      { recipient-id: recipient-id }
      {
        name: name,
        location: location,
        category: category,
        verification-status: "pending",
        total-received: u0,
        project-count: u0,
        consent-given: true,
        contact-method: contact-method
      }
    )
    (var-set recipient-counter counter)
    (ok recipient-id)
  )
)

;; Create transparency report
(define-public (create-transparency-report
    (project-id (string-ascii 64))
    (funds-utilized uint)
    (beneficiaries-served uint)
    (milestones-completed uint)
    (efficiency-metrics (list 5 uint))
    (challenges-faced (string-ascii 512))
    (next-steps (string-ascii 256))
  )
  (let (
    (project-info (unwrap! (map-get? charitable-projects { project-id: project-id }) err-not-found))
    (report-id u1) ;; Simple counter for now
  )
    (asserts! (is-authorized-org (get org-id project-info)) err-unauthorized)
    
    (map-set transparency-reports
      { project-id: project-id, report-id: report-id }
      {
        report-date: block-height,
        funds-utilized: funds-utilized,
        beneficiaries-served: beneficiaries-served,
        milestones-completed: milestones-completed,
        efficiency-metrics: efficiency-metrics,
        challenges-faced: challenges-faced,
        next-steps: next-steps,
        verification-status: "published"
      }
    )
    
    (ok report-id)
  )
)

;; Read-only functions

;; Get organization info
(define-read-only (get-organization (org-id (string-ascii 64)))
  (map-get? charitable-organizations { org-id: org-id })
)

;; Get project info
(define-read-only (get-project (project-id (string-ascii 64)))
  (map-get? charitable-projects { project-id: project-id })
)

;; Get donation info
(define-read-only (get-donation (donation-id (string-ascii 64)))
  (map-get? donations { donation-id: donation-id })
)

;; Get milestone info
(define-read-only (get-milestone (project-id (string-ascii 64)) (milestone-id uint))
  (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id })
)

;; Get recipient info
(define-read-only (get-recipient (recipient-id (string-ascii 64)))
  (map-get? recipients { recipient-id: recipient-id })
)

;; Get transparency report
(define-read-only (get-transparency-report (project-id (string-ascii 64)) (report-id uint))
  (map-get? transparency-reports { project-id: project-id, report-id: report-id })
)

;; Get platform statistics
(define-read-only (get-platform-stats)
  {
    total-organizations: (var-get org-counter),
    total-projects: (var-get project-counter),
    total-donations: (var-get donation-counter),
    total-recipients: (var-get recipient-counter),
    total-donated: (var-get total-platform-donations),
    platform-fee: (var-get platform-fee-percentage)
  }
)

;; Check if organization is verified
(define-read-only (is-organization-verified (org-id (string-ascii 64)))
  (is-authorized-org org-id)
)

;; Calculate project completion percentage
(define-read-only (get-project-progress (project-id (string-ascii 64)))
  (match (map-get? charitable-projects { project-id: project-id })
    project-info
    (let (
      (total-milestones (get milestone-count project-info))
      (completed (get completed-milestones project-info))
    )
      (if (> total-milestones u0)
        (/ (* completed u100) total-milestones)
        u0
      )
    )
    u0
  )
)


;; title: donation-tracking-system
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

