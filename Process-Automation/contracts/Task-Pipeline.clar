;; Cross-Organizational Workflow Automation Smart Contract
;; This contract manages workflows across multiple organizations with automated task execution

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_STATE (err u102))
(define-constant ERR_ALREADY_EXISTS (err u103))
(define-constant ERR_INVALID_PARTICIPANT (err u104))
(define-constant ERR_WORKFLOW_COMPLETED (err u105))
(define-constant ERR_INSUFFICIENT_APPROVALS (err u106))
(define-constant ERR_DEADLINE_PASSED (err u107))
(define-constant ERR_INVALID_DEADLINE (err u108))
(define-constant ERR_INVALID_INPUT (err u109))

;; Workflow states
(define-constant STATE_DRAFT u0)
(define-constant STATE_ACTIVE u1)
(define-constant STATE_PAUSED u2)
(define-constant STATE_COMPLETED u3)
(define-constant STATE_CANCELLED u4)

;; Task states
(define-constant TASK_PENDING u0)
(define-constant TASK_IN_PROGRESS u1)
(define-constant TASK_COMPLETED u2)
(define-constant TASK_REJECTED u3)
(define-constant TASK_CANCELLED u4)

;; Data structures
(define-map workflows
  { workflow-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    creator: principal,
    state: uint,
    created-at: uint,
    deadline: uint,
    participants: (list 20 principal),
    required-approvals: uint,
    current-approvals: uint,
    completion-reward: uint
  }
)

(define-map tasks
  { workflow-id: uint, task-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    assignee: principal,
    state: uint,
    created-at: uint,
    deadline: uint,
    dependencies: (list 10 uint),
    completion-proof: (optional (string-ascii 100)),
    approvers: (list 10 principal),
    approvals-received: uint,
    required-approvals: uint
  }
)

(define-map organizations
  { org-id: principal }
  {
    name: (string-ascii 50),
    admin: principal,
    members: (list 50 principal),
    reputation: uint,
    active: bool
  }
)

(define-map workflow-participants
  { workflow-id: uint, participant: principal }
  { role: (string-ascii 20), permissions: uint }
)

(define-map task-approvals
  { workflow-id: uint, task-id: uint, approver: principal }
  { approved: bool, timestamp: uint, comments: (string-ascii 100) }
)

(define-map workflow-approvals
  { workflow-id: uint, approver: principal }
  { approved: bool, timestamp: uint }
)

(define-map user-profiles
  { user: principal }
  {
    reputation: uint,
    completed-tasks: uint,
    active-workflows: uint,
    organizations: (list 10 principal)
  }
)

;; Data variables
(define-data-var workflow-counter uint u0)
(define-data-var task-counter uint u0)
(define-data-var contract-paused bool false)

;; Input validation functions
(define-private (validate-string-not-empty (str (string-ascii 200)))
  (> (len str) u0)
)

(define-private (validate-workflow-id (workflow-id uint))
  (and (> workflow-id u0) (<= workflow-id (var-get workflow-counter)))
)

(define-private (validate-task-id (task-id uint))
  (and (> task-id u0) (<= task-id (var-get task-counter)))
)

(define-private (validate-deadline (deadline uint))
  (> deadline block-height)
)

(define-private (validate-participants-list (participants (list 20 principal)))
  (> (len participants) u0)
)

(define-private (validate-members-list (members (list 50 principal)))
  (>= (len members) u0)
)

(define-private (validate-approvers-list (approvers (list 10 principal)))
  (> (len approvers) u0)
)

(define-private (validate-dependencies-list (dependencies (list 10 uint)))
  (>= (len dependencies) u0)
)

;; Private functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (is-workflow-participant (workflow-id uint) (user principal))
  (let ((workflow (unwrap! (map-get? workflows { workflow-id: workflow-id }) false)))
    (is-some (index-of (get participants workflow) user))
  )
)

(define-private (is-organization-member (org-id principal) (user principal))
  (let ((org (unwrap! (map-get? organizations { org-id: org-id }) false)))
    (is-some (index-of (get members org) user))
  )
)

(define-private (can-execute-task (workflow-id uint) (task-id uint))
  (let (
    (task (unwrap! (map-get? tasks { workflow-id: workflow-id, task-id: task-id }) false))
    (workflow (unwrap! (map-get? workflows { workflow-id: workflow-id }) false))
  )
    (and
      (is-eq (get state workflow) STATE_ACTIVE)
      (is-eq (get state task) TASK_PENDING)
      (<= block-height (get deadline task))
      (>= (get approvals-received task) (get required-approvals task))
    )
  )
)

(define-private (check-task-dependencies (workflow-id uint) (dependencies (list 10 uint)))
  (fold check-dependency-completed dependencies true)
)

(define-private (check-dependency-completed (task-id uint) (acc bool))
  (if (not acc)
    false
    (let ((task (map-get? tasks { workflow-id: u0, task-id: task-id })))
      (match task
        task-data (is-eq (get state task-data) TASK_COMPLETED)
        false
      )
    )
  )
)

(define-private (update-user-reputation (user principal) (points uint))
  (let ((profile (default-to 
    { reputation: u0, completed-tasks: u0, active-workflows: u0, organizations: (list) }
    (map-get? user-profiles { user: user }))))
    (map-set user-profiles { user: user }
      (merge profile { reputation: (+ (get reputation profile) points) })
    )
  )
)

(define-private (increment-completed-tasks (user principal))
  (let ((profile (default-to 
    { reputation: u0, completed-tasks: u0, active-workflows: u0, organizations: (list) }
    (map-get? user-profiles { user: user }))))
    (map-set user-profiles { user: user }
      (merge profile { completed-tasks: (+ (get completed-tasks profile) u1) })
    )
  )
)

;; Public functions

;; Organization management
(define-public (register-organization (name (string-ascii 50)) (members (list 50 principal)))
  (begin
    (asserts! (not (var-get contract-paused)) ERR_INVALID_STATE)
    (asserts! (is-none (map-get? organizations { org-id: tx-sender })) ERR_ALREADY_EXISTS)
    (asserts! (validate-string-not-empty name) ERR_INVALID_INPUT)
    (asserts! (validate-members-list members) ERR_INVALID_INPUT)
    (map-set organizations { org-id: tx-sender }
      {
        name: name,
        admin: tx-sender,
        members: members,
        reputation: u100,
        active: true
      }
    )
    (ok tx-sender)
  )
)

(define-public (add-organization-member (org-id principal) (new-member principal))
  (begin
    (asserts! (not (is-eq org-id 'SP000000000000000000002Q6VF78)) ERR_INVALID_INPUT)
    (let ((org (unwrap! (map-get? organizations { org-id: org-id }) ERR_NOT_FOUND)))
      (asserts! (is-eq (get admin org) tx-sender) ERR_UNAUTHORIZED)
      (asserts! (get active org) ERR_INVALID_STATE)
      (asserts! (is-none (index-of (get members org) new-member)) ERR_ALREADY_EXISTS)
      (map-set organizations { org-id: org-id }
        (merge org { members: (unwrap! (as-max-len? (append (get members org) new-member) u50) ERR_INVALID_PARTICIPANT) })
      )
      (ok true)
    )
  )
)

;; Workflow management
(define-public (create-workflow 
  (name (string-ascii 50))
  (description (string-ascii 200))
  (participants (list 20 principal))
  (deadline uint)
  (required-approvals uint)
  (completion-reward uint)
)
  (let ((workflow-id (+ (var-get workflow-counter) u1)))
    (asserts! (not (var-get contract-paused)) ERR_INVALID_STATE)
    (asserts! (validate-deadline deadline) ERR_INVALID_DEADLINE)
    (asserts! (validate-string-not-empty name) ERR_INVALID_INPUT)
    (asserts! (validate-string-not-empty description) ERR_INVALID_INPUT)
    (asserts! (validate-participants-list participants) ERR_INVALID_INPUT)
    (asserts! (<= required-approvals (len participants)) ERR_INVALID_PARTICIPANT)
    (asserts! (>= completion-reward u0) ERR_INVALID_INPUT)
    
    (map-set workflows { workflow-id: workflow-id }
      {
        name: name,
        description: description,
        creator: tx-sender,
        state: STATE_DRAFT,
        created-at: block-height,
        deadline: deadline,
        participants: participants,
        required-approvals: required-approvals,
        current-approvals: u0,
        completion-reward: completion-reward
      }
    )
    (var-set workflow-counter workflow-id)
    (ok workflow-id)
  )
)

(define-public (activate-workflow (workflow-id uint))
  (let ((workflow (unwrap! (map-get? workflows { workflow-id: workflow-id }) ERR_NOT_FOUND)))
    (asserts! (validate-workflow-id workflow-id) ERR_INVALID_INPUT)
    (asserts! (is-eq (get creator workflow) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get state workflow) STATE_DRAFT) ERR_INVALID_STATE)
    (map-set workflows { workflow-id: workflow-id }
      (merge workflow { state: STATE_ACTIVE })
    )
    (ok true)
  )
)

(define-public (pause-workflow (workflow-id uint))
  (let ((workflow (unwrap! (map-get? workflows { workflow-id: workflow-id }) ERR_NOT_FOUND)))
    (asserts! (validate-workflow-id workflow-id) ERR_INVALID_INPUT)
    (asserts! (is-eq (get creator workflow) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get state workflow) STATE_ACTIVE) ERR_INVALID_STATE)
    (map-set workflows { workflow-id: workflow-id }
      (merge workflow { state: STATE_PAUSED })
    )
    (ok true)
  )
)

(define-public (resume-workflow (workflow-id uint))
  (let ((workflow (unwrap! (map-get? workflows { workflow-id: workflow-id }) ERR_NOT_FOUND)))
    (asserts! (validate-workflow-id workflow-id) ERR_INVALID_INPUT)
    (asserts! (is-eq (get creator workflow) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get state workflow) STATE_PAUSED) ERR_INVALID_STATE)
    (map-set workflows { workflow-id: workflow-id }
      (merge workflow { state: STATE_ACTIVE })
    )
    (ok true)
  )
)

(define-public (approve-workflow (workflow-id uint))
  (let ((workflow (unwrap! (map-get? workflows { workflow-id: workflow-id }) ERR_NOT_FOUND)))
    (asserts! (validate-workflow-id workflow-id) ERR_INVALID_INPUT)
    (asserts! (is-workflow-participant workflow-id tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get state workflow) STATE_ACTIVE) ERR_INVALID_STATE)
    (asserts! (is-none (map-get? workflow-approvals { workflow-id: workflow-id, approver: tx-sender })) ERR_ALREADY_EXISTS)
    
    (map-set workflow-approvals { workflow-id: workflow-id, approver: tx-sender }
      { approved: true, timestamp: block-height }
    )
    
    (let ((new-approvals (+ (get current-approvals workflow) u1)))
      (map-set workflows { workflow-id: workflow-id }
        (merge workflow { current-approvals: new-approvals })
      )
      
      ;; Check if workflow can be completed
      (if (>= new-approvals (get required-approvals workflow))
        (map-set workflows { workflow-id: workflow-id }
          (merge workflow { state: STATE_COMPLETED })
        )
        false
      )
    )
    (ok true)
  )
)

;; Task management
(define-public (create-task
  (workflow-id uint)
  (name (string-ascii 50))
  (description (string-ascii 200))
  (assignee principal)
  (deadline uint)
  (dependencies (list 10 uint))
  (approvers (list 10 principal))
  (required-approvals uint)
)
  (let (
    (task-id (+ (var-get task-counter) u1))
    (workflow (unwrap! (map-get? workflows { workflow-id: workflow-id }) ERR_NOT_FOUND))
  )
    (asserts! (validate-workflow-id workflow-id) ERR_INVALID_INPUT)
    (asserts! (validate-string-not-empty name) ERR_INVALID_INPUT)
    (asserts! (validate-string-not-empty description) ERR_INVALID_INPUT)
    (asserts! (validate-deadline deadline) ERR_INVALID_DEADLINE)
    (asserts! (validate-dependencies-list dependencies) ERR_INVALID_INPUT)
    (asserts! (validate-approvers-list approvers) ERR_INVALID_INPUT)
    (asserts! (is-eq (get creator workflow) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get state workflow) STATE_DRAFT) ERR_INVALID_STATE)
    (asserts! (<= deadline (get deadline workflow)) ERR_INVALID_DEADLINE)
    (asserts! (is-workflow-participant workflow-id assignee) ERR_INVALID_PARTICIPANT)
    (asserts! (<= required-approvals (len approvers)) ERR_INVALID_PARTICIPANT)
    
    (map-set tasks { workflow-id: workflow-id, task-id: task-id }
      {
        name: name,
        description: description,
        assignee: assignee,
        state: TASK_PENDING,
        created-at: block-height,
        deadline: deadline,
        dependencies: dependencies,
        completion-proof: none,
        approvers: approvers,
        approvals-received: u0,
        required-approvals: required-approvals
      }
    )
    (var-set task-counter task-id)
    (ok task-id)
  )
)

(define-public (start-task (workflow-id uint) (task-id uint))
  (let ((task (unwrap! (map-get? tasks { workflow-id: workflow-id, task-id: task-id }) ERR_NOT_FOUND)))
    (asserts! (validate-workflow-id workflow-id) ERR_INVALID_INPUT)
    (asserts! (validate-task-id task-id) ERR_INVALID_INPUT)
    (asserts! (is-eq (get assignee task) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get state task) TASK_PENDING) ERR_INVALID_STATE)
    (asserts! (check-task-dependencies workflow-id (get dependencies task)) ERR_INVALID_STATE)
    (asserts! (<= block-height (get deadline task)) ERR_DEADLINE_PASSED)
    
    (map-set tasks { workflow-id: workflow-id, task-id: task-id }
      (merge task { state: TASK_IN_PROGRESS })
    )
    (ok true)
  )
)

(define-public (complete-task (workflow-id uint) (task-id uint) (proof (string-ascii 100)))
  (let ((task (unwrap! (map-get? tasks { workflow-id: workflow-id, task-id: task-id }) ERR_NOT_FOUND)))
    (asserts! (validate-workflow-id workflow-id) ERR_INVALID_INPUT)
    (asserts! (validate-task-id task-id) ERR_INVALID_INPUT)
    (asserts! (validate-string-not-empty proof) ERR_INVALID_INPUT)
    (asserts! (is-eq (get assignee task) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get state task) TASK_IN_PROGRESS) ERR_INVALID_STATE)
    (asserts! (<= block-height (get deadline task)) ERR_DEADLINE_PASSED)
    
    (map-set tasks { workflow-id: workflow-id, task-id: task-id }
      (merge task { 
        state: TASK_COMPLETED,
        completion-proof: (some proof)
      })
    )
    
    ;; Update user statistics
    (increment-completed-tasks tx-sender)
    (update-user-reputation tx-sender u10)
    
    (ok true)
  )
)

(define-public (approve-task (workflow-id uint) (task-id uint) (comments (string-ascii 100)))
  (let ((task (unwrap! (map-get? tasks { workflow-id: workflow-id, task-id: task-id }) ERR_NOT_FOUND)))
    (asserts! (validate-workflow-id workflow-id) ERR_INVALID_INPUT)
    (asserts! (validate-task-id task-id) ERR_INVALID_INPUT)
    (asserts! (validate-string-not-empty comments) ERR_INVALID_INPUT)
    (asserts! (is-some (index-of (get approvers task) tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get state task) TASK_COMPLETED) ERR_INVALID_STATE)
    (asserts! (is-none (map-get? task-approvals { workflow-id: workflow-id, task-id: task-id, approver: tx-sender })) ERR_ALREADY_EXISTS)
    
    (map-set task-approvals { workflow-id: workflow-id, task-id: task-id, approver: tx-sender }
      { approved: true, timestamp: block-height, comments: comments }
    )
    
    (let ((new-approvals (+ (get approvals-received task) u1)))
      (map-set tasks { workflow-id: workflow-id, task-id: task-id }
        (merge task { approvals-received: new-approvals })
      )
    )
    (ok true)
  )
)

(define-public (reject-task (workflow-id uint) (task-id uint) (reason (string-ascii 100)))
  (let ((task (unwrap! (map-get? tasks { workflow-id: workflow-id, task-id: task-id }) ERR_NOT_FOUND)))
    (asserts! (validate-workflow-id workflow-id) ERR_INVALID_INPUT)
    (asserts! (validate-task-id task-id) ERR_INVALID_INPUT)
    (asserts! (validate-string-not-empty reason) ERR_INVALID_INPUT)
    (asserts! (is-some (index-of (get approvers task) tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get state task) TASK_COMPLETED) ERR_INVALID_STATE)
    
    (map-set task-approvals { workflow-id: workflow-id, task-id: task-id, approver: tx-sender }
      { approved: false, timestamp: block-height, comments: reason }
    )
    
    (map-set tasks { workflow-id: workflow-id, task-id: task-id }
      (merge task { 
        state: TASK_REJECTED,
        completion-proof: none
      })
    )
    (ok true)
  )
)

;; Administrative functions
(define-public (pause-contract)
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (resume-contract)
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-workflow (workflow-id uint))
  (map-get? workflows { workflow-id: workflow-id })
)

(define-read-only (get-task (workflow-id uint) (task-id uint))
  (map-get? tasks { workflow-id: workflow-id, task-id: task-id })
)

(define-read-only (get-organization (org-id principal))
  (map-get? organizations { org-id: org-id })
)

(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { user: user })
)

(define-read-only (get-workflow-approval (workflow-id uint) (approver principal))
  (map-get? workflow-approvals { workflow-id: workflow-id, approver: approver })
)

(define-read-only (get-task-approval (workflow-id uint) (task-id uint) (approver principal))
  (map-get? task-approvals { workflow-id: workflow-id, task-id: task-id, approver: approver })
)

(define-read-only (get-workflow-counter)
  (var-get workflow-counter)
)

(define-read-only (get-task-counter)
  (var-get task-counter)
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (can-approve-workflow (workflow-id uint) (user principal))
  (let ((workflow (unwrap! (map-get? workflows { workflow-id: workflow-id }) false)))
    (and
      (is-workflow-participant workflow-id user)
      (is-eq (get state workflow) STATE_ACTIVE)
      (is-none (map-get? workflow-approvals { workflow-id: workflow-id, approver: user }))
    )
  )
)

(define-read-only (can-approve-task (workflow-id uint) (task-id uint) (user principal))
  (let ((task (unwrap! (map-get? tasks { workflow-id: workflow-id, task-id: task-id }) false)))
    (and
      (is-some (index-of (get approvers task) user))
      (is-eq (get state task) TASK_COMPLETED)
      (is-none (map-get? task-approvals { workflow-id: workflow-id, task-id: task-id, approver: user }))
    )
  )
)