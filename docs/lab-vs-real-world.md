# Lab vs real world

Shortcuts I took in this lab and what a real bank would do instead.

| In my lab | At a real bank |
|---|---|
| Agent requests are tables in `agent-intake.md` | A request form in ServiceNow or a GRC tool, with an approval workflow and an audit trail |
| One person, the AI Risk Officer, reviews every agent request | Risk, security, data privacy and IAM each review it, and the high-risk ones may go to a committee |
| 4 staff made by hand in Entra | Staff come from the HR system and get made by a joiner process |
| I took the web search tool off each agent by hand, since its data leaves the Azure compliance boundary | The platform team blocks it for every agent with a policy, so no builder can turn it on |
| Security defaults for MFA | Conditional Access policies, which need Entra ID P1. I skipped them because I already use Conditional Access at work |
| The AI-002 blob tool on Azure Functions is open to the internet with no key. It has no access of its own and only passes the caller's token on, so storage makes every access decision | The tool sits behind a private endpoint or an API gateway and checks the token itself before it forwards anything, so only the bank's agents can reach it |
| Henrik tested the agent in the Foundry build portal, so he needed Foundry User on the project for the test. That role also lets someone change or delete agents, so I removed it right after | Staff use the agent through Teams or a web page and only get Foundry Agent Consumer on that one agent, given with Azure CLI or a script |
| To test the storage block on its own, I saved a short test version of AI-002's instructions on the same agent identity, ran the HR read, then saved the real instructions back | Control tests run against a separate test agent in a test environment with the same role setup, so the live agent never runs test instructions |
| I run the inventory script by hand, signed in as myself | It runs on a schedule as its own read-only identity, and new flags open a ticket for the agent's sponsor and IAM |
| The disable request is a Logic App run, and Nanna approves from an email that forwards to my Gmail. The email can't prove she was the one who clicked | The request is a ServiceNow ticket or an IGA request (Danske Bank and Bankdata run ServiceNow), and the approver decides in Teams or Outlook while signed in, so the decision is tied to her account |
| I turned off key access on the one Foundry resource by hand with Azure CLI, and turned it back on for a few minutes to prove an old key gets turned away | An Azure Policy blocks keys on every AI resource, so a new one never starts with keys on. If keys have to be cut during an incident, the bank also regenerates them, since an old key kept working for 2 to 4 minutes after the switch |
| The Logic App only knows the request came from the Foundry project identity. Who asked comes from the agent's message, checked against `/v1.0/me` | The request system takes the requester from the signed-in session itself, so an agent can't put a different name on it |
| The first approval email went to Gmail's Spam, and Nanna's "inbox" is my Gmail | The approval shows up in the approver's own work queue, like a ServiceNow approval or a Teams approval, signed in as her |
| The approval request only reaches one approver, with no backup and no time limit | Approvals have a backup approver and expire, so a request doesn't sit forever and someone is always there to decide |
| When Louise left, I moved AI-002's sponsor to Henrik by hand after the inventory flagged it | A leaver workflow moves sponsorship to the manager on the same day, with Agent 365 or another IGA tool, and emails the manager |
| I disabled Louise by hand in Entra to act as a leaver | HR ends the job and the leaver process disables the account, then hands her agents and access to her manager |
| I offboarded AI-002 by clicking through Entra, Azure and Foundry, then checked by object ID | An offboarding ticket lists every piece the agent owns, and a script or the IGA tool removes them and closes the ticket with the evidence |
| The inventory only lists agent identities. The Logic App identity that can disable staff accounts for AI-001, and the app registration that only exists for AI-001, don't show on its row | The inventory lists every identity that acts for an agent or exists only for it, so the agent's full reach is on one row |
| Entra ID Free doesn't let Graph read sign-in logs, so I checked agent sign-ins in the portal by hand | Sign-in and audit logs stream to the bank's SIEM, and agent sign-ins get their own alerts |
