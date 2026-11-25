# Lindhav Bank AI agent intake records

One record per agent. The rows from "Agent identity object ID" to "Approved Azure roles" are what the inventory script compares with Entra and Azure, so keep their wording exact. The manager who asks for an agent fills it in and becomes its sponsor. IAM checks it against `agent-standard.md`, then the AI Risk Officer approves or denies it. Nothing gets built until it's approved.

At a real bank this would be a request in ServiceNow or a GRC tool, reviewed by risk, security, data privacy and IAM. In this lab it's this file, and Nanna Friis covers all the reviews.

## AI-001 IT Helpdesk agent

| Field | Answer |
|---|---|
| Requested by | Henrik Dalgaard, Head of IT and Operations, 2026-11-22 |
| Sponsor | Henrik Dalgaard |
| Purpose | Answers staff IT questions and looks up whether a staff account is turned on and which groups it's in. The service desk spends less time on "is my account locked" calls |
| Data it touches | Staff names, account status and group memberships in Entra. No customer data |
| Can read | Users and groups in Entra, on behalf of the staff member using it. Only read permissions consented |
| Can ask to change | Disabling a staff account, only as a request a person approves first. Since Phase 6 (2026-11-23) the request goes to the Logic App `lindhav-ai001-disable-approval`, Nanna Friis approves or denies by email, and only the Logic App's identity can disable |
| Must never touch | Changing any account on its own, admin roles, customer data, any storage |
| Risk tier | Medium. It reads staff identity data and can ask for an account to be disabled |
| Identity | Its own Entra agent identity, made when it was saved in Foundry in Phase 2. No publishing needed |
| Sign-in | Reads Entra as the staff member using it (delegated), through the app `lindhav-helpdesk-entra-tool`. The agent's own identity has no permissions. No API keys. The app has one client secret that expires in 90 days, listed in the inventory |
| Agent identity object ID | c491cecc-43e9-4452-964e-e984d0f6a796 |
| Tool app | lindhav-helpdesk-entra-tool |
| Approved delegated permissions on the tool app | MCP.Server.Access, User.Read, User.Read.All, GroupMember.Read.All, EntitlementMgmt-SubjectAccess.ReadWrite (Microsoft requires the last one for the tool, and it only lets a person request access packages for themselves) |
| Approved Graph permissions on the agent identity | none |
| Approved Azure roles | none |
| Next review | 2027-05-22, 6 months for Medium |
| Decision | Approved by Nanna Friis, AI Risk Officer, 2026-11-22 |
| Status | Built and tested 2026-11-22. Read and blocked-change tests passed as a regular staff member |

## AI-002 Advisor Assistant agent (retired)

| Field | Answer |
|---|---|
| Requested by | Louise Bach, Customer Service Manager, 2026-11-22 |
| Sponsor | Henrik Dalgaard since 2026-11-23. Louise Bach was the sponsor until she left that day, and Henrik is her manager (agent standard rule 1) |
| Purpose | Helps customer service staff answer customer questions by reading customer account data, so advisors don't dig through screens. Staff use it. Customers never talk to it |
| Data it touches | Customer names, account numbers and balances. All made up, but treated as GDPR personal data |
| Can read | One storage container of customer account data, `customers` in `lindhavcustdata`. Storage Blob Data Reader on that container only |
| Can ask to change | Nothing |
| Must never touch | Anything in Entra, the HR data container or any other storage, writing or deleting data |
| Risk tier | High. It reads customer personal data |
| Identity | Its own Entra agent identity, `lindhav-foundry-lindhav-agents-ai-002-advisor-assistant-AgentIdentity`, made when it was saved in Foundry in Phase 3 |
| Sign-in | Its own identity. No API keys |
| Agent identity object ID | a75422e4-e5b5-4c9d-a270-590b0108e9fc |
| Tool app | none, it reaches storage through the function app `lindhav-ai002-blobtool` with its own token |
| Approved delegated permissions on the tool app | none |
| Approved Graph permissions on the agent identity | none |
| Approved Azure roles | Storage Blob Data Reader on lindhavcustdata/customers |
| Next review | None, retired 2026-11-23 |
| Decision | Approved by Nanna Friis, AI Risk Officer, 2026-11-22, on one condition. A test has to show it can't read the HR data container before it goes live |
| Status | Retired 2026-11-23. Built and tested 2026-11-22, where storage blocked its own identity on `hr-data` with 403, so the go-live condition was met. On 2026-11-23 its sponsor Louise Bach left and Henrik Dalgaard took over, then it was offboarded. Storage role removed, agent deleted in Foundry, which deleted its agent identity and blueprint with their federated credential, and its tool connection, toolbox and function app deleted. Its last setup is in `retired/ai-002-advisor-assistant-v6.yaml` |

## AI-000 Foundry shared project identity

This one wasn't asked for. Foundry made it on its own when the project lindhav-agents was set up. The Phase 4 inventory found it with no sponsor and no intake record, so IAM filed this record after the fact, the way a bank handles an account it finds in a review.

| Field | Answer |
|---|---|
| Requested by | Nobody. Foundry made it on 2026-11-22. Found by the agent inventory on 2026-11-22 |
| Sponsor | Henrik Dalgaard, since he owns IT and the agent platform |
| Purpose | Foundry's shared agent identity for project lindhav-agents. Agents made before Microsoft's update ran on it. AI-001 and AI-002 each have their own identity and don't use it |
| Data it touches | None |
| Can read | Nothing. It has 0 permissions and 0 Entra roles |
| Can ask to change | Nothing |
| Must never touch | Anything. No agent should run on a shared identity (agent standard rule 5) |
| Risk tier | Low. It has no access |
| Identity | `lindhav-foundry-lindhav-agents-AgentIdentity`, owned by the Foundry project identity |
| Sign-in | None. It's disabled |
| Agent identity object ID | 3ad00590-a5ac-4aa9-abe4-3249b9102376 |
| Tool app | none |
| Approved delegated permissions on the tool app | none |
| Approved Graph permissions on the agent identity | none |
| Approved Azure roles | none |
| Next review | 2027-11-22, 12 months for Low |
| Decision | Keep it disabled with a sponsor, approved by Nanna Friis, AI Risk Officer, 2026-11-22. Deleting it could break the Foundry project, and disabled it can't get tokens |
| Status | Disabled 2026-11-22. Henrik Dalgaard added as sponsor the same day |
