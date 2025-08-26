;; EduChain Credentials - Soulbound NFT Certificates System
;; Issues non-transferable NFT certificates for educational achievements

;; --- Constants ---
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-CERTIFICATE-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-EXISTS (err u405))
(define-constant ERR-INVALID-ISSUER (err u406))
(define-constant ERR-TRANSFER-RESTRICTED (err u407))
(define-constant ERR-INVALID-PARAMETERS (err u408))
(define-constant ERR-BATCH-LIMIT-EXCEEDED (err u409))
(define-constant ERR-CERTIFICATE-EXPIRED (err u410))

;; --- Data Variables ---
(define-data-var next-certificate-id uint u1)
(define-data-var contract-uri (string-utf8 256) u"")
(define-data-var max-batch-size uint u20)

;; --- Data Maps ---
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

;; --- NFT Trait Implementation (Soulbound - Non-transferable) ---
(define-non-fungible-token edu-certificate uint)

;; --- Private Helper Functions ---

;; Helper function to check if a certificate matches skill level
(define-private (certificate-matches-skill-level (cert-id uint) (target-skill-level (string-ascii 20)))
  (match (map-get? certificates cert-id)
    cert (and (not (get revoked cert)) (is-eq (get skill-level cert) target-skill-level))
    false))

;; Helper function to get valid certificate credits
(define-private (get-certificate-credits (cert-id uint))
  (match (map-get? certificates cert-id)
    cert (if (and (not (get revoked cert)) 
                 (match (get expiry-date cert)
                   expiry (< block-height expiry)
                   true))
           (get credits cert)
           u0)
    u0))

;; Helper function for batch processing
(define-private (process-single-batch-certificate (recipient principal) (course-name (string-utf8 100)) (grade (string-ascii 10)) (metadata-uri (string-utf8 256)) (credits uint) (skill-level (string-ascii 20)))
  (let ((certificate-id (var-get next-certificate-id)))
    (asserts! (is-none (map-get? certificate-verification {recipient: recipient, course-name: course-name})) ERR-ALREADY-EXISTS)
    
    ;; Mint and store data
    (try! (nft-mint? edu-certificate certificate-id recipient))
    (map-set certificates certificate-id {
      recipient: recipient,
      issuer: tx-sender,
      course-name: course-name,
      completion-date: block-height,
      grade: grade,
      certificate-hash: "batch-issued", ;; Placeholder hash for batch
      metadata-uri: metadata-uri,
      revoked: false,
      expiry-date: none,
      credits: credits,
      skill-level: skill-level
    })
    
    ;; Update recipient and verification maps
    (let ((current-certs (default-to (list) (map-get? recipient-certificates recipient))))
      (map-set recipient-certificates recipient (unwrap! (as-max-len? (append current-certs certificate-id) u100) ERR-ALREADY-EXISTS)))
    (map-set certificate-verification {recipient: recipient, course-name: course-name} certificate-id)
    
    (var-set next-certificate-id (+ certificate-id u1))
    (ok certificate-id)
  ))

;; Helper function to process batch using fold
(define-private (process-batch-fold (recipient principal) (acc {course-name: (string-utf8 100), grade: (string-ascii 10), metadata-uri: (string-utf8 256), credits: uint, skill-level: (string-ascii 20), results: (list 20 uint), success: bool}))
  (if (get success acc)
    (match (process-single-batch-certificate recipient (get course-name acc) (get grade acc) (get metadata-uri acc) (get credits acc) (get skill-level acc))
      success-id {
        course-name: (get course-name acc),
        grade: (get grade acc), 
        metadata-uri: (get metadata-uri acc),
        credits: (get credits acc),
        skill-level: (get skill-level acc),
        results: (unwrap! (as-max-len? (append (get results acc) success-id) u20) (get results acc)),
        success: true
      }
      error {
        course-name: (get course-name acc),
        grade: (get grade acc),
        metadata-uri: (get metadata-uri acc), 
        credits: (get credits acc),
        skill-level: (get skill-level acc),
        results: (get results acc),
        success: false
      })
    acc))

;; --- Public Functions ---

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

;; Issue a single certificate
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
    
    (try! (nft-mint? edu-certificate certificate-id recipient))
    
    (map-set certificates certificate-id {
      recipient: recipient, issuer: tx-sender, course-name: course-name, 
      completion-date: block-height, grade: grade, certificate-hash: certificate-hash,
      metadata-uri: metadata-uri, revoked: false, expiry-date: expiry-date,
      credits: credits, skill-level: skill-level
    })
    
    (let ((current-certs (default-to (list) (map-get? recipient-certificates recipient))))
      (map-set recipient-certificates recipient (unwrap! (as-max-len? (append current-certs certificate-id) u100) ERR-ALREADY-EXISTS)))
    
    (map-set certificate-verification {recipient: recipient, course-name: course-name} certificate-id)
    (map-set authorized-issuers tx-sender (merge issuer-info {issued-count: (+ (get issued-count issuer-info) u1)}))
    
    (var-set next-certificate-id (+ certificate-id u1))
    (ok certificate-id)))

;; Batch issue certificates
(define-public (batch-issue-certificates 
  (recipients (list 20 principal))
  (course-name (string-utf8 100))
  (grade (string-ascii 10))
  (metadata-uri (string-utf8 256))
  (credits uint)
  (skill-level (string-ascii 20)))
  (let (
    (issuer-info (unwrap! (map-get? authorized-issuers tx-sender) ERR-INVALID-ISSUER))
    (batch-size (len recipients))
    (batch-id (var-get next-certificate-id))
  )
    (asserts! (get active issuer-info) ERR-NOT-AUTHORIZED)
    (asserts! (<= batch-size (var-get max-batch-size)) ERR-BATCH-LIMIT-EXCEEDED)
    (asserts! (<= (+ (get issued-count issuer-info) batch-size) (get max-issuance issuer-info)) ERR-NOT-AUTHORIZED)
    
    ;; Process all certificates using fold
    (let ((batch-result (fold process-batch-fold recipients {
            course-name: course-name,
            grade: grade,
            metadata-uri: metadata-uri,
            credits: credits,
            skill-level: skill-level,
            results: (list),
            success: true
          })))
      (asserts! (get success batch-result) ERR-INVALID-PARAMETERS)
      (let ((issued-ids (get results batch-result)))
        (map-set authorized-issuers tx-sender (merge issuer-info {issued-count: (+ (get issued-count issuer-info) batch-size)}))
        (map-set batch-operations batch-id {
          operator: tx-sender, operation-type: "BATCH_ISSUE", 
          timestamp: block-height, certificates: issued-ids, status: "COMPLETED"
        })
        (ok issued-ids)
      )
    )
  ))



;; Revoke a certificate
(define-public (revoke-certificate (certificate-id uint))
  (let ((cert (unwrap! (map-get? certificates certificate-id) ERR-CERTIFICATE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get issuer cert)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get revoked cert)) ERR-ALREADY-EXISTS)
    (map-set certificates certificate-id (merge cert {revoked: true}))
    (ok true)))

;; Update certificate metadata
(define-public (update-certificate-metadata (certificate-id uint) (new-metadata-uri (string-utf8 256)))
  (let ((cert (unwrap! (map-get? certificates certificate-id) ERR-CERTIFICATE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get issuer cert)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get revoked cert)) ERR-CERTIFICATE-NOT-FOUND)
    (map-set certificates certificate-id (merge cert {metadata-uri: new-metadata-uri}))
    (ok true)))

;; Extend certificate expiry
(define-public (extend-certificate-expiry (certificate-id uint) (new-expiry uint))
  (let ((cert (unwrap! (map-get? certificates certificate-id) ERR-CERTIFICATE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get issuer cert)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get revoked cert)) ERR-CERTIFICATE-NOT-FOUND)
    (asserts! (> new-expiry block-height) ERR-INVALID-PARAMETERS)
    (map-set certificates certificate-id (merge cert {expiry-date: (some new-expiry)}))
    (ok true)))

;; Create course template
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
      duration-blocks: duration-blocks, required-grade: required-grade, 
      credits: credits, prerequisites: prerequisites, active: true
    })
    (ok true)))

;; Prevent transfers (Soulbound implementation)
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  ERR-TRANSFER-RESTRICTED)

;; --- Read-only Functions ---

;; Get certificate details
(define-read-only (get-certificate (certificate-id uint))
  (map-get? certificates certificate-id))

;; Verify certificate authenticity by hash
(define-read-only (verify-certificate (certificate-id uint) (expected-hash (string-ascii 64)))
  (let ((cert (unwrap! (map-get? certificates certificate-id) ERR-CERTIFICATE-NOT-FOUND)))
    (asserts! (not (get revoked cert)) ERR-CERTIFICATE-NOT-FOUND)
    (ok (is-eq (get certificate-hash cert) expected-hash))))

;; Get all certificate IDs for a recipient
(define-read-only (get-recipient-certificates (recipient principal))
  (map-get? recipient-certificates recipient))

;; Get certificates by skill level - FIXED VERSION
(define-read-only (get-certificates-by-skill-level (recipient principal) (target-skill-level (string-ascii 20)))
  (match (map-get? recipient-certificates recipient)
    cert-ids (ok (fold check-skill-level cert-ids {target: target-skill-level, result: (list)}))
    (ok (list))))

;; Helper function for filtering certificates by skill level
(define-private (check-skill-level (cert-id uint) (data {target: (string-ascii 20), result: (list 100 uint)}))
  (let ((target-skill (get target data))
        (current-result (get result data)))
    (if (certificate-matches-skill-level cert-id target-skill)
        {target: target-skill, result: (unwrap! (as-max-len? (append current-result cert-id) u100) current-result)}
        data)))

;; Get issuer statistics
(define-read-only (get-issuer-statistics (issuer principal))
  (match (map-get? authorized-issuers issuer)
    info (ok {
      issued-count: (get issued-count info),
      max-issuance: (get max-issuance info),
      remaining-quota: (- (get max-issuance info) (get issued-count info)),
      active: (get active info),
      institution: (get institution info)
    })
    (err ERR-INVALID-ISSUER)))
    
;; Verify if a recipient has completed a course
(define-read-only (verify-completion (recipient principal) (course-name (string-utf8 100)))
  (match (map-get? certificate-verification {recipient: recipient, course-name: course-name})
    cert-id (let ((cert (unwrap! (map-get? certificates cert-id) (err false))))
              (and (not (get revoked cert))
                   (match (get expiry-date cert)
                     expiry (< block-height expiry)
                     true)))
    false))

;; Get total credits for a recipient from valid certificates - FIXED VERSION
(define-read-only (get-total-credits (recipient principal))
  (match (map-get? recipient-certificates recipient)
    cert-ids (fold + (map get-certificate-credits cert-ids) u0)
    u0))

;; Get info about an authorized issuer
(define-read-only (get-issuer-info (issuer principal))
  (map-get? authorized-issuers issuer))

;; Get total number of certificates issued
(define-read-only (get-certificate-count)
  (ok (- (var-get next-certificate-id) u1)))

;; Check if an issuer is authorized and active
(define-read-only (is-authorized-issuer (issuer principal))
  (match (map-get? authorized-issuers issuer)
    info (get active info)
    false))

;; Get a course template
(define-read-only (get-course-template (course-name (string-utf8 100)))
  (map-get? course-templates course-name))

;; Check if a certificate is expired
(define-read-only (is-certificate-expired (certificate-id uint))
  (match (map-get? certificates certificate-id)
    cert (match (get expiry-date cert)
           expiry (>= block-height expiry)
           false)
    false))

;; Get info about a batch operation
(define-read-only (get-batch-operation (batch-id uint))
  (map-get? batch-operations batch-id))

;; --- SIP-009 NFT Trait Functions ---
(define-read-only (get-last-token-id)
  (ok (- (var-get next-certificate-id) u1)))

(define-read-only (get-token-uri (token-id uint))
  (ok (some (get metadata-uri (unwrap! (map-get? certificates token-id) (err none))))))

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? edu-certificate token-id)))

;; --- Contract Metadata ---
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