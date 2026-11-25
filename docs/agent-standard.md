# Lindhav Bank AI agent standard

Version 1, 2026-11-22. Owned by IAM. Approved by Nanna Friis, AI Risk Officer.

Every AI agent at Lindhav Bank is an identity, the same as an employee or a service account. No agent goes live until it meets every rule on this page and the AI Risk Officer approves its intake record in `agent-intake.md`.

## The rules

1. Every agent has one named sponsor. That's the business person who asked for it and answers for what it does. It's always a person, never a team or a shared mailbox. If the sponsor leaves, their manager becomes the sponsor until a new one is picked.
2. Every agent has a written purpose of one or two sentences. It does that job and nothing else. If the job changes, the agent goes through intake again.
3. Every agent gets a tier based on the data it reads and what it can ask to change. The tier sets how often it's reviewed. The table is below.
4. The intake record says what the agent can read, what it can ask to change, and what it must never touch. It gets only what's on the list. IAM tests at least one thing on the "never touch" list and keeps the blocked result as proof.
5. Each agent has its own Entra agent identity. No agent runs on a person's account or shares an identity with another agent. Then the logs show which agent did what, and one agent can be turned off without touching the others.
6. Agents sign in with their own identity, not an API key or password that anyone else could also use. If a secret can't be avoided, it expires in 90 days or less and it's listed in the agent inventory.
7. An agent can read on its own. Anything that changes data or access, like creating, changing, disabling or deleting, is a request. A person approves or denies it before anything happens. The record keeps who asked, who decided and when.
8. Every agent has a next review date set by its tier. At review, the sponsor confirms the agent is still needed and still used, and IAM checks its access still matches the intake record. An agent that misses its review gets disabled until the review is done.
9. IAM can disable any agent's identity right away if it acts wrong, without waiting for the sponsor. When an agent isn't needed anymore, it's offboarded like a leaver. Access removed, credentials deleted, identity disabled and then deleted, and the intake record marked retired.

## Risk tiers

| Tier | What puts an agent in this tier | Review every |
|---|---|---|
| Low | Reads only internal info that isn't about people. Can't ask for changes | 12 months |
| Medium | Reads staff or identity data, or can ask for changes to accounts or access | 6 months |
| High | Reads customer data or any other personal data covered by GDPR | 3 months |

When an agent fits more than one tier, it gets the highest one.
