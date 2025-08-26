;; Collaboration Hub Contract
;; Manages partnerships between designers and manufacturers

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-PROJECT-EXISTS (err u401))
(define-constant ERR-PROJECT-NOT-FOUND (err u402))
(define-constant ERR-INVALID-STATUS (err u403))
(define-constant ERR-INVALID-PARTICIPANT (err u404))

;; Project Status Constants
(define-constant STATUS-PROPOSED u1)
(define-constant STATUS-ACCEPTED u2)
(define-constant STATUS-IN-PROGRESS u3)
(define-constant STATUS-COMPLETED u4)
(define-constant STATUS-CANCELLED u5)

;; Data Variables
(define-data-var next-project-id uint u1)

;; Data Maps
(define-map collaboration-projects
  { project-id: uint }
  {
    designer: principal,
    manufacturer: principal,
    design-id: uint,
    title: (string-ascii 100),
    description: (string-ascii 500),
    status: uint,
    created-at: uint,
    deadline: uint,
    budget: uint,
    designer-share: uint, ;; Percentage in basis points
    manufacturer-share: uint
  }
)

(define-map project-milestones
  { project-id: uint, milestone-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 300),
    deadline: uint,
    completed: bool,
    completed-at: (optional uint),
    payment-amount: uint
  }
)

(define-map project-agreements
  { project-id: uint }
  {
    terms: (string-ascii 500),
    designer-signed: bool,
    manufacturer-signed: bool,
    signed-at: (optional uint),
    ip-ownership: (string-ascii 200)
  }
)

(define-map participant-projects
  { participant: principal, project-id: uint }
  { role: (string-ascii 20), joined-at: uint }
)

;; Public Functions

;; Propose a new collaboration project
(define-public (propose-collaboration (manufacturer principal)
                                    (design-id uint)
                                    (title (string-ascii 100))
                                    (description (string-ascii 500))
                                    (deadline uint)
                                    (budget uint)
                                    (designer-share uint)
                                    (terms (string-ascii 500)))
  (let ((project-id (var-get next-project-id)))

    ;; Validate inputs
    (asserts! (not (is-eq tx-sender manufacturer)) ERR-INVALID-PARTICIPANT)
    (asserts! (> (len title) u0) ERR-INVALID-STATUS)
    (asserts! (> deadline block-height) ERR-INVALID-STATUS)
    (asserts! (> budget u0) ERR-INVALID-STATUS)
    (asserts! (<= designer-share u10000) ERR-INVALID-STATUS) ;; Max 100%

    ;; Create project
    (map-set collaboration-projects
      { project-id: project-id }
      {
        designer: tx-sender,
        manufacturer: manufacturer,
        design-id: design-id,
        title: title,
        description: description,
        status: STATUS-PROPOSED,
        created-at: block-height,
        deadline: deadline,
        budget: budget,
        designer-share: designer-share,
        manufacturer-share: (- u10000 designer-share)
      }
    )

    ;; Set project agreement
    (map-set project-agreements
      { project-id: project-id }
      {
        terms: terms,
        designer-signed: true,
        manufacturer-signed: false,
        signed-at: none,
        ip-ownership: "Shared as per agreement"
      }
    )

    ;; Track participants
    (map-set participant-projects
      { participant: tx-sender, project-id: project-id }
      { role: "designer", joined-at: block-height }
    )

    (map-set participant-projects
      { participant: manufacturer, project-id: project-id }
      { role: "manufacturer", joined-at: block-height }
    )

    ;; Increment project ID
    (var-set next-project-id (+ project-id u1))

    (ok project-id)
  )
)

;; Accept a collaboration proposal
(define-public (accept-collaboration (project-id uint))
  (let ((project (unwrap! (map-get? collaboration-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
        (agreement (unwrap! (map-get? project-agreements { project-id: project-id }) ERR-PROJECT-NOT-FOUND)))

    ;; Check authorization (must be manufacturer)
    (asserts! (is-eq tx-sender (get manufacturer project)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status project) STATUS-PROPOSED) ERR-INVALID-STATUS)

    ;; Update project status
    (map-set collaboration-projects
      { project-id: project-id }
      (merge project { status: STATUS-ACCEPTED })
    )

    ;; Update agreement
    (map-set project-agreements
      { project-id: project-id }
      (merge agreement {
        manufacturer-signed: true,
        signed-at: (some block-height)
      })
    )

    (ok true)
  )
)

;; Start project work
(define-public (start-project (project-id uint))
  (let ((project (unwrap! (map-get? collaboration-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND)))

    ;; Check authorization (designer or manufacturer)
    (asserts! (or (is-eq tx-sender (get designer project))
                  (is-eq tx-sender (get manufacturer project))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status project) STATUS-ACCEPTED) ERR-INVALID-STATUS)

    ;; Update status to in-progress
    (map-set collaboration-projects
      { project-id: project-id }
      (merge project { status: STATUS-IN-PROGRESS })
    )

    (ok true)
  )
)

;; Add project milestone
(define-public (add-milestone (project-id uint)
                             (milestone-id uint)
                             (title (string-ascii 100))
                             (description (string-ascii 300))
                             (deadline uint)
                             (payment-amount uint))
  (let ((project (unwrap! (map-get? collaboration-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND)))

    ;; Check authorization
    (asserts! (or (is-eq tx-sender (get designer project))
                  (is-eq tx-sender (get manufacturer project))) ERR-NOT-AUTHORIZED)

    ;; Validate inputs
    (asserts! (> (len title) u0) ERR-INVALID-STATUS)
    (asserts! (> deadline block-height) ERR-INVALID-STATUS)

    ;; Add milestone
    (map-set project-milestones
      { project-id: project-id, milestone-id: milestone-id }
      {
        title: title,
        description: description,
        deadline: deadline,
        completed: false,
        completed-at: none,
        payment-amount: payment-amount
      }
    )

    (ok true)
  )
)

;; Complete a milestone
(define-public (complete-milestone (project-id uint) (milestone-id uint))
  (let ((project (unwrap! (map-get? collaboration-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
        (milestone (unwrap! (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id }) ERR-PROJECT-NOT-FOUND)))

    ;; Check authorization
    (asserts! (or (is-eq tx-sender (get designer project))
                  (is-eq tx-sender (get manufacturer project))) ERR-NOT-AUTHORIZED)
    (asserts! (not (get completed milestone)) ERR-INVALID-STATUS)

    ;; Mark milestone as completed
    (map-set project-milestones
      { project-id: project-id, milestone-id: milestone-id }
      (merge milestone {
        completed: true,
        completed-at: (some block-height)
      })
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get project information
(define-read-only (get-project (project-id uint))
  (map-get? collaboration-projects { project-id: project-id })
)

;; Get project agreement
(define-read-only (get-project-agreement (project-id uint))
  (map-get? project-agreements { project-id: project-id })
)

;; Get milestone information
(define-read-only (get-milestone (project-id uint) (milestone-id uint))
  (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id })
)

;; Check if user is project participant
(define-read-only (is-project-participant (project-id uint) (user principal))
  (is-some (map-get? participant-projects { participant: user, project-id: project-id }))
)

;; Get user's role in project
(define-read-only (get-user-role (project-id uint) (user principal))
  (map-get? participant-projects { participant: user, project-id: project-id })
)

;; Check if project is fully signed
(define-read-only (is-project-signed (project-id uint))
  (match (map-get? project-agreements { project-id: project-id })
    agreement (and (get designer-signed agreement) (get manufacturer-signed agreement))
    false
  )
)
