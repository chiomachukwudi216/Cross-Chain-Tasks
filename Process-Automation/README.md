# Cross-Organizational Workflow Automation Smart Contract

## Overview

This Clarity smart contract provides a comprehensive workflow automation system designed for managing collaborative processes across multiple organizations. It enables the creation, management, and execution of complex workflows with automated task dependencies, multi-party approvals, and reputation tracking.

## Features

### Core Functionality
- **Multi-organizational support**: Register and manage organizations with members and admins
- **Workflow management**: Create, activate, pause, resume, and complete workflows
- **Task management**: Create dependent tasks with automated execution logic
- **Approval systems**: Multi-party approval mechanisms for workflows and tasks
- **Reputation tracking**: User reputation system based on task completion
- **Deadline enforcement**: Time-based constraints for workflows and tasks
- **Access control**: Role-based permissions and authorization

### Key Capabilities
- Cross-organizational collaboration
- Automated dependency checking
- Proof of completion verification
- Reputation-based incentive system
- Administrative controls and pausing mechanisms

## Data Structures

### Workflows
Each workflow contains:
- Basic information (name, description, creator)
- State management (draft, active, paused, completed, cancelled)
- Participant list and approval requirements
- Deadline and completion rewards
- Progress tracking

### Tasks
Task properties include:
- Assignment details and dependencies
- State tracking (pending, in progress, completed, rejected, cancelled)
- Approval requirements and proof submission
- Deadline enforcement

### Organizations
Organization structure:
- Name and administrative details
- Member management
- Reputation scoring
- Active status control

### User Profiles
User tracking includes:
- Reputation points
- Task completion statistics
- Active workflow participation
- Organization memberships

## States and Constants

### Workflow States
- `STATE_DRAFT` (0): Initial creation state
- `STATE_ACTIVE` (1): Workflow is active and executing
- `STATE_PAUSED` (2): Temporarily suspended
- `STATE_COMPLETED` (3): Successfully finished
- `STATE_CANCELLED` (4): Terminated workflow

### Task States
- `TASK_PENDING` (0): Awaiting execution
- `TASK_IN_PROGRESS` (1): Currently being worked on
- `TASK_COMPLETED` (2): Finished and awaiting approval
- `TASK_REJECTED` (3): Rejected by approvers
- `TASK_CANCELLED` (4): Cancelled task

## Functions

### Organization Management

#### `register-organization`
```clarity
(register-organization (name (string-ascii 50)) (members (list 50 principal)))
```
Registers a new organization with specified name and member list.

#### `add-organization-member`
```clarity
(add-organization-member (org-id principal) (new-member principal))
```
Adds a new member to an existing organization (admin only).

### Workflow Management

#### `create-workflow`
```clarity
(create-workflow 
  (name (string-ascii 50))
  (description (string-ascii 200))
  (participants (list 20 principal))
  (deadline uint)
  (required-approvals uint)
  (completion-reward uint))
```
Creates a new workflow in draft state with specified parameters.

#### `activate-workflow`
```clarity
(activate-workflow (workflow-id uint))
```
Activates a draft workflow (creator only).

#### `pause-workflow` / `resume-workflow`
```clarity
(pause-workflow (workflow-id uint))
(resume-workflow (workflow-id uint))
```
Pauses or resumes an active workflow (creator only).

#### `approve-workflow`
```clarity
(approve-workflow (workflow-id uint))
```
Approves a workflow as a participant, contributing to completion requirements.

### Task Management

#### `create-task`
```clarity
(create-task
  (workflow-id uint)
  (name (string-ascii 50))
  (description (string-ascii 200))
  (assignee principal)
  (deadline uint)
  (dependencies (list 10 uint))
  (approvers (list 10 principal))
  (required-approvals uint))
```
Creates a new task within a workflow with dependencies and approval requirements.

#### `start-task`
```clarity
(start-task (workflow-id uint) (task-id uint))
```
Starts a pending task (assignee only, dependencies must be completed).

#### `complete-task`
```clarity
(complete-task (workflow-id uint) (task-id uint) (proof (string-ascii 100)))
```
Marks a task as completed with proof submission.

#### `approve-task` / `reject-task`
```clarity
(approve-task (workflow-id uint) (task-id uint) (comments (string-ascii 100)))
(reject-task (workflow-id uint) (task-id uint) (reason (string-ascii 100)))
```
Approves or rejects completed tasks (approvers only).

### Administrative Functions

#### `pause-contract` / `resume-contract`
```clarity
(pause-contract)
(resume-contract)
```
Global contract pause/resume functionality (contract owner only).

## Read-Only Functions

### Data Retrieval
- `get-workflow`: Retrieve workflow details
- `get-task`: Retrieve task information
- `get-organization`: Get organization data
- `get-user-profile`: Fetch user profile information
- `get-workflow-approval` / `get-task-approval`: Check approval status

### Status Checks
- `get-workflow-counter` / `get-task-counter`: Current ID counters
- `is-contract-paused`: Contract pause status
- `can-approve-workflow` / `can-approve-task`: Permission validation

## Error Codes

- `ERR_UNAUTHORIZED` (100): Insufficient permissions
- `ERR_NOT_FOUND` (101): Resource not found
- `ERR_INVALID_STATE` (102): Invalid state for operation
- `ERR_ALREADY_EXISTS` (103): Resource already exists
- `ERR_INVALID_PARTICIPANT` (104): Invalid participant or parameter
- `ERR_WORKFLOW_COMPLETED` (105): Workflow already completed
- `ERR_INSUFFICIENT_APPROVALS` (106): Not enough approvals
- `ERR_DEADLINE_PASSED` (107): Deadline has passed
- `ERR_INVALID_DEADLINE` (108): Invalid deadline specified

## Usage Examples

### Basic Workflow Creation
1. Register organizations using `register-organization`
2. Create workflow with `create-workflow`
3. Add tasks using `create-task` with appropriate dependencies
4. Activate workflow with `activate-workflow`
5. Participants execute tasks and provide approvals
6. Workflow completes automatically when requirements are met

### Task Execution Flow
1. Task assignee calls `start-task` when dependencies are met
2. Assignee completes work and calls `complete-task` with proof
3. Approvers review and call `approve-task` or `reject-task`
4. Task completion updates user reputation automatically

## Security Considerations

- Role-based access control throughout all functions
- Deadline enforcement prevents stale task execution
- Dependency checking ensures proper task ordering
- Multi-party approval system prevents single points of failure
- Contract owner emergency controls for system maintenance

## Deployment Notes

- Contract owner is set to the deploying principal
- All counters start at 0
- Contract starts in unpaused state
- Reputation system rewards task completion with 10 points
- Maximum limits: 50 org members, 20 workflow participants, 10 task dependencies