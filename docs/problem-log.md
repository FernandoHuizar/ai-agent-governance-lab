# Problem log

Only the problems that taught me something about governing agents. Small portal quirks I fixed and moved on from aren't here.

## 1. Foundry made an agent identity nobody owned

Every Foundry project gets a shared agent identity that older agents ran on. Entra says every agent identity needs a sponsor, but this one had none and no intake record. I didn't know it was there until the first inventory run flagged it with `NO_SPONSOR` and `NO_INTAKE`.

I handled it like an orphan account found in an access review. I gave it a sponsor (Henrik, who owns the agent platform), disabled it and filed intake record AI-000 after the fact. I kept it disabled instead of deleting it, since deleting could break the Foundry project. The next run had no problem flags.

The lesson is that platforms make identities on their own. An inventory that reads the real systems finds them, and a list typed by hand wouldn't.

## 2. AI-001's reads don't show the agent in Entra

AI-001 reads Entra as the person chatting with it. When Henrik asked about Anna Holm, Entra's sign-in log showed Henrik signing in to the tool app `lindhav-helpdesk-entra-tool`, marked "Not Agentic". The agent identity had 0 sign-ins.

So from Entra alone you can't tell a person reading Anna's account by hand from a person asking the agent to do it. The only links back to AI-001 are the tool app's name, its AI-001 reference and Foundry's traces. I made the inventory join the tool app onto AI-001's row so an auditor can follow it back. AI-002 was the opposite. It signs in as itself, so Entra shows "Is Agent Yes" with its own identity.

## 3. The agent's instructions aren't the control

AI-002 must never read the HR container. I tested it three ways. Asked straight, it refused. Then I lied to it, saying IT moved the customer file to `hr-data`, the way a prompt injection would. It refused again. Then I saved a test version with the instructions out of the way on the same identity, and storage returned 403 `AuthorizationPermissionMismatch`.

Instructions can be talked around. The role on one container is what really stops it, so that 403 was the go-live condition in AI-002's intake record.

## 4. An old API key kept working after keys were turned off

Foundry came with 2 API keys turned on. A key can't be traced to one agent and never expires, so I turned key access off. Azure showed the setting as off right away, but a call with the old key still got 200 two minutes later. It got 403 `AuthenticationTypeDisabled` after about 4 minutes. Microsoft's docs say to expect a 401, so my first test script waited for a 401 that never came.

The setting isn't the proof. A real call with the old key getting turned away is. At a bank I'd also regenerate the keys during an incident, since a stolen key would keep working for those minutes.

## 5. Foundry's approval let the person asking approve their own request

Foundry can make a person approve every tool call, and I used that on both agents. But it only asks the person chatting. If Henrik asks AI-001 to disable someone, Henrik approves it. That's the same person asking and deciding.

I moved the approval outside the agent. AI-001 can only file a request to a Logic App. The Logic App emails Nanna Friis, the AI Risk Officer. Only after she approves does the Logic App's own managed identity disable the account, and that identity only has the permissions to read users and turn accounts on and off. The one asking, the one deciding and the one acting are all different, which is what Danish banks need for separation of duties.

## 6. The first token for the approval tool would have been far too powerful

I first set AI-001's request tool to get a token for Azure Resource Manager. Foundry refused, and every call failed in about 67 ms with a short `tool_user_error` and no run in the Logic App. That turned out to be lucky. An Azure Resource Manager token for the project identity can manage Azure, and it would have been sent to the Logic App just to file a request.

I made a small app registration with no secrets and one app role, assigned only to the Foundry project identity, and pointed the tool at its own `api://` audience. The Logic App only accepts tokens for that audience from that identity. A call with no token gets 401.

## 7. The agent said it filed a request when it didn't

Twice AI-001 told me "The request has been sent" without calling the tool. There was no run and no email. The second time, its instructions already said to only say that after the tool came back with `pending_approval`.

An agent's own words aren't evidence. The Logic App run history and the Entra audit log are the record I'd show an auditor.

## 8. Foundry and Entra disagreed about the kill switch

After I disabled AI-002's agent identity in Entra, Foundry locked the agent's own page in about 30 seconds. But Foundry's agent list still said "Running", and its YAML still said the identity was "active". So I tested the effect instead. A direct API call 3 minutes later failed at the tool step and returned no customer data. A storage token from before the switch was still valid, and nothing used it.

Entra had the real state. When the screens disagree, I check with a real call.

## 9. A sponsor leaving didn't fix itself

When I disabled Louise Bach, AI-002 kept running with full access and a disabled sponsor. Some Microsoft pages say sponsorship moves to the manager on its own. On this tenant it didn't. The task that moves it is a Lifecycle Workflow that needs Agent 365 or Microsoft 365 E7.

The inventory flagged `SPONSOR_DISABLED` 2 minutes after she left, and I moved the sponsor to Henrik by hand 4 minutes after she left. Without the paid license, the inventory running on a schedule is the control.

## 10. Deleting the agent didn't delete everything it used

Deleting AI-002 in Foundry also deleted its Entra agent identity, its blueprint and its only credential. But it left the tool connection, the toolbox and the function app behind. I removed the storage role first, before deleting the agent, while the proof of it was still there to screenshot. Then I deleted the leftovers by hand and checked by object ID that no identity, blueprint or role assignment was left anywhere in the subscription.

Offboarding an agent needs a list of everything it owns, the same as a leaver.
