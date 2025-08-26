;; EduChain Credentials - Soulbound NFT Certificates System
;; Issues non-transferable NFT certificates for educational achievements

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-CERTIFICATE-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-EXISTS (err u405))
(define-constant ERR-INVALID-ISSUER (err u406))
(define-constant ERR-TRANSFER-RESTRICTED (err u407))
(define-constant ERR-INVALID-PARAMETERS (err u408))
(define-constant ERR-BATCH-LIMIT-EXCEEDED (err u409))
(define-constant ERR-CERTIFICATE-EXPIRED (err u410))

;; Data Variables
(define-data-var next-certificate-id uint u1)
(define-data-var contract-uri (string-utf8 256) u"")
(define-data-var max-batch-size uint u20)

;; Data Maps
(define-map certificates
  uint
  {
    recipient: principal,
    issuer: principal,
    course-name: (string-utf8 100),
    completion-date: uint,
    grade: (string-ascii 10),
    certificate-hash: (string-ascii 64),
    metadata-uri: (string-utf8 256),
    revoked: bool,
    expiry-date: (optional uint),
    credits: uint,
    skill-level: (string-ascii 20)
  })

(define-map authorized-issuers
  principal
  {
    institution: (string-utf8 100),
    authorized-by: principal,
    active: bool,
    issued-count: uint,
    max-issuance: uint
  })

(define-map recipient-certificates
  principal
  (list 100 uint))

(define-map certificate-verification
  {recipient: principal, course-name: (string-utf8 100)}
  uint)

(define-map course-templates
  (string-utf8 100)
  {
    duration-blocks: uint,
    required-grade: (string-ascii 10),
    credits: uint,
    prerequisites: (list 5 (string-utf8 100)),
    active: bool
  })

(define-map batch-operations
  uint
  {
    operator: principal,
    operation-type: (string-ascii 20),
    timestamp: uint,
    certificates: (list 20 uint),
    status: (string-ascii 10)
  })

;; NFT Trait Implementation (Soulbound - Non-transferable)
(define-non-fungible-token edu-certificate uint)

;; Public Functions

;; Add authorized issuer (only owner)
(define-public (authorize-issuer (issuer principal) (institution (string-utf8 100)) (max-issuance uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> max-issuance u0) ERR-INVALID-PARAMETERS)
    (map-set authorized-issuers issuer {
      institution: institution,
      authorized-by: tx-sender,
      active: true,
      issued-count: u0,
      max-issuance: max-issuance
    })
    (ok true)))

;; Issue a certificate (only authorized issuers)
(define-public (issue-certificate 
  (recipient principal) 
  (course-name (string-utf8 100)) 
  (grade (string-ascii 10))
  (certificate-hash (string-ascii 64))
  (metadata-uri (string-utf8 256))
  (expiry-date (optional uint))
  (credits uint)
  (skill-level (string-ascii 20)))
  (let (
    (certificate-id (var-get next-certificate-id))
    (issuer-info (unwrap! (map-get? authorized-issuers tx-sender) ERR-INVALID-ISSUER))
  )
    (asserts! (get active issuer-info) ERR-NOT-AUTHORIZED)
    (asserts! (< (get issued-count issuer-info) (get max-issuance issuer-info)) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? certificate-verification {recipient: recipient, course-name: course-name})) ERR-ALREADY-EXISTS)
    
    ;; Mint soulbound NFT
    (try! (nft-mint? edu-certificate certificate-id recipient))
    
    ;; Store certificate data
    (map-set certificates certificate-id {
      recipient: recipient,
      issuer: tx-sender,
      course-name: course-name,
      completion-date: block-height,
      grade: grade,
      certificate-hash: certificate-hash,
      metadata-uri: metadata-uri,
      revoked: false,
      expiry-date: expiry-date,
      credits: credits,
      skill-level: skill-level
    })
    
    ;; Update recipient's certificate list (fixed list limit)
    (let ((current-certs (default-to (list) (map-get? recipient-certificates recipient))))
      (map-set recipient-certificates recipient (unwrap! (as-max-len? (append current-certs certificate-id) u100) ERR-ALREADY-EXISTS)))
    
    ;; Add verification mapping
    (map-set certificate-verification {recipient: recipient, course-name: course-name} certificate-id)
    
    ;; Update issuer count
    (map-set authorized-issuers tx-sender (merge issuer-info {issued-count: (+ (get issued-count issuer-info) u1)}))
    
    (var-set next-certificate-id (+ certificate-id u1))
    (ok certificate-id)))

;; Revoke a certificate
(define-public (revoke-certificate (certificate-id uint))
  (let ((cert (unwrap! (map-get? certificates certificate-id) ERR-CERTIFICATE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get issuer cert)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get revoked cert)) ERR-ALREADY-EXISTS)
    
    (map-set certificates certificate-id (merge cert {revoked: true}))
    (ok true)))

;; Verify certificate authenticity
(define-public (verify-certificate (certificate-id uint) (expected-hash (string-ascii 64)))
  (let ((cert (unwrap! (map-get? certificates certificate-id) ERR-CERTIFICATE-NOT-FOUND)))
    (asserts! (not (get revoked cert)) ERR-CERTIFICATE-NOT-FOUND)
    (ok (is-eq (get certificate-hash cert) expected-hash))))

;; Prevent transfers (Soulbound implementation)
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  ERR-TRANSFER-RESTRICTED)

;; NEW FUNCTION 1: Batch issue certificates
(define-public (batch-issue-certificates 
  (recipients (list 20 principal))
  (course-name (string-utf8 100))
  (grade (string-ascii 10))
  (metadata-uri (string-utf8 256))
  (credits uint)
  (skill-level (string-ascii 20)))
  (let (
    (batch-id (var-get next-certificate-id))
    (issuer-info (unwrap! (map-get? authorized-issuers tx-sender) ERR-INVALID-ISSUER))
    (batch-size (len recipients))
  )
    (asserts! (get active issuer-info) ERR-NOT-AUTHORIZED)
    (asserts! (<= batch-size (var-get max-batch-size)) ERR-BATCH-LIMIT-EXCEEDED)
    (asserts! (<= (+ (get issued-count issuer-info) batch-size) (get max-issuance issuer-info)) ERR-NOT-AUTHORIZED)
    
    ;; Process batch
    (let ((result (fold process-batch-certificate recipients (ok (list)))))
      (match result
        success (begin
          (map-set batch-operations batch-id {
            operator: tx-sender,
            operation-type: "BATCH_ISSUE",
            timestamp: block-height,
            certificates: success,
            status: "COMPLETED"
          })
          (ok success))
        error (err error)))))

;; NEW FUNCTION 2: Create course template
(define-public (create-course-template 
  (course-name (string-utf8 100))
  (duration-blocks uint)
  (required-grade (string-ascii 10))
  (credits uint)
  (prerequisites (list 5 (string-utf8 100))))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> duration-blocks u0) ERR-INVALID-PARAMETERS)
    (asserts! (> credits u0) ERR-INVALID-PARAMETERS)
    
    (map-set course-templates course-name {
      duration-blocks: duration-blocks,
      required-grade: required-grade,
      credits: credits,
      prerequisites: prerequisites,
      active: true
    })
    (ok true)))

;; NEW FUNCTION 3: Update certificate metadata
(define-public (update-certificate-metadata (certificate-id uint) (new-metadata-uri (string-utf8 256)))
  (let ((cert (unwrap! (map-get? certificates certificate-id) ERR-CERTIFICATE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get issuer cert)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get revoked cert)) ERR-CERTIFICATE-NOT-FOUND)
    
    (map-set certificates certificate-id (merge cert {metadata-uri: new-metadata-uri}))
    (ok true)))

;; NEW FUNCTION 4: Get certificates by skill level
(define-read-only (get-certificates-by-skill-level (recipient principal) (target-skill-level (string-ascii 20)))
  (let ((cert-ids (default-to (list) (map-get? recipient-certificates recipient))))
    (get result (fold filter-certificates-by-skill cert-ids {skill-level: target-skill-level, result: (list)}))))

;; NEW FUNCTION 5: Extend certificate expiry
(define-public (extend-certificate-expiry (certificate-id uint) (new-expiry uint))
  (let ((cert (unwrap! (map-get? certificates certificate-id) ERR-CERTIFICATE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get issuer cert)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get revoked cert)) ERR-CERTIFICATE-NOT-FOUND)
    (asserts! (> new-expiry block-height) ERR-INVALID-PARAMETERS)
    
    (map-set certificates certificate-id (merge cert {expiry-date: (some new-expiry)}))
    (ok true)))

;; NEW FUNCTION 6: Get issuer statistics
(define-public (get-issuer-statistics (issuer principal))
  (let ((issuer-info (map-get? authorized-issuers issuer)))
    (match issuer-info
      info (ok {
        issued-count: (get issued-count info),
        max-issuance: (get max-issuance info),
        remaining-quota: (- (get max-issuance info) (get issued-count info)),
        active: (get active info),
        institution: (get institution info)
      })
      (err ERR-INVALID-ISSUER))))

;; Helper function for batch processing
(define-private (process-batch-certificate (recipient principal) (acc-response (response (list 20 uint) uint)))
  (match acc-response
    acc-list 
      (let ((cert-id (var-get next-certificate-id)))
        (match (nft-mint? edu-certificate cert-id recipient)
          success (begin
            (var-set next-certificate-id (+ cert-id u1))
            (ok (unwrap! (as-max-len? (append acc-list cert-id) u20) ERR-BATCH-LIMIT-EXCEEDED)))
          error (err error)))
    error (err error)))

;; Helper function for filtering certificates by skill level
(define-private (filter-certificates-by-skill (cert-id uint) (context {skill-level: (string-ascii 20), result: (list 100 uint)}))
  (let ((target-skill (get skill-level context))
        (current-result (get result context)))
    (match (map-get? certificates cert-id)
      cert (if (and (not (get revoked cert)) 
                    (is-eq (get skill-level cert) target-skill))
             {skill-level: target-skill, result: (unwrap! (as-max-len? (append current-result cert-id) u100) current-result)}
             context)
      context)))

;; Read-only Functions

(define-read-only (get-certificate (certificate-id uint))
  (map-get? certificates certificate-id))

(define-read-only (get-recipient-certificates (recipient principal))
  (map-get? recipient-certificates recipient))

(define-read-only (verify-completion (recipient principal) (course-name (string-utf8 100)))
  (match (map-get? certificate-verification {recipient: recipient, course-name: course-name})
    cert-id (let ((cert (map-get? certificates cert-id)))
              (match cert
                certificate (and (not (get revoked certificate))
                               (is-eq (get recipient certificate) recipient)
                               (match (get expiry-date certificate)
                                 expiry (< block-height expiry)
                                 true))
                false))
    false))

(define-read-only (get-issuer-info (issuer principal))
  (map-get? authorized-issuers issuer))

(define-read-only (get-certificate-count)
  (- (var-get next-certificate-id) u1))

(define-read-only (is-authorized-issuer (issuer principal))
  (match (map-get? authorized-issuers issuer)
    info (get active info)
    false))

(define-read-only (get-course-template (course-name (string-utf8 100)))
  (map-get? course-templates course-name))

(define-read-only (is-certificate-expired (certificate-id uint))
  (match (map-get? certificates certificate-id)
    cert (match (get expiry-date cert)
            expiry (>= block-height expiry)
            false)
    false))

(define-read-only (get-total-credits (recipient principal))
  (let ((cert-ids (default-to (list) (map-get? recipient-certificates recipient))))
    (fold + 
      (map (lambda (cert-id)
        (match (map-get? certificates cert-id)
          cert (if (and (not (get revoked cert)) 
                       (match (get expiry-date cert)
                         expiry (< block-height expiry)
                         true))
                 (get credits cert)
                 u0)
          u0)) cert-ids) u0)))

(define-read-only (get-batch-operation (batch-id uint))
  (map-get? batch-operations batch-id))

;; NFT Trait Functions
(define-read-only (get-last-token-id)
  (ok (- (var-get next-certificate-id) u1)))

(define-read-only (get-token-uri (token-id uint))
  (let ((cert (map-get? certificates token-id)))
    (match cert
      certificate (ok (some (get metadata-uri certificate)))
      (ok none))))

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? edu-certificate token-id)))

;; Contract metadata
(define-read-only (get-contract-uri)
  (ok (var-get contract-uri)))

(define-public (set-contract-uri (uri (string-utf8 256)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-uri uri)
    (ok true)))

(define-public (set-max-batch-size (new-size uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-size u0) ERR-INVALID-PARAMETERS)
    (var-set max-batch-size new-size)
    (ok true)))