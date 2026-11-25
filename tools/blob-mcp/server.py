"""
Read-only blob MCP tool for the Advisor Assistant (AI-002).

What it does
  A tiny MCP server with two tools, list_files and read_file. Foundry signs in
  as the agent's own identity, gets a token for https://storage.azure.com and
  sends it here in the Authorization header. This server hands that same token
  to the Blob REST API. So storage checks the agent's own role assignment, and
  a container the agent has no role on (hr-data) fails with a 403 from storage.
  The code never blocks a container itself.

Inputs
  list_files(container)        container name, like customers
  read_file(container, name)   container name and file name, like customers.csv
  The bearer token from the incoming request. No keys, SAS or connection strings.

Outputs
  list_files returns one file name per line.
  read_file returns the file's text.
  Storage errors come back as plain text, like "403 AuthorizationPermissionMismatch".

How to run
  It runs on Azure Functions (Flex Consumption) as a self-hosted MCP server,
  see host.json. The endpoint is https://<app>.azurewebsites.net/mcp
  Locally it's `python server.py`, which listens on port 8000.

The token is never logged or returned.
"""

import logging
import os
import xml.etree.ElementTree as ET
from urllib.parse import quote

import httpx
from mcp.server.fastmcp import Context, FastMCP

BLOB_ENDPOINT = "https://lindhavcustdata.blob.core.windows.net"
STORAGE_API_VERSION = "2025-01-05"

# Keep logs quiet so nothing near the request headers gets written out.
logging.basicConfig(level=logging.WARNING)
logging.getLogger("httpx").setLevel(logging.WARNING)

port = int(os.environ.get("FUNCTIONS_CUSTOMHANDLER_PORT", "8000"))
mcp = FastMCP("lindhav-blob-reader", host="0.0.0.0", port=port, stateless_http=True)


def get_token(ctx: Context) -> str | None:
    request = ctx.request_context.request
    if request is None:
        return None
    auth = request.headers.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        return None
    return auth[7:].strip() or None


def call_storage(token: str, path: str) -> httpx.Response:
    headers = {"Authorization": f"Bearer {token}", "x-ms-version": STORAGE_API_VERSION}
    return httpx.get(f"{BLOB_ENDPOINT}/{path}", headers=headers, timeout=30)


def storage_error(resp: httpx.Response) -> str:
    code = resp.headers.get("x-ms-error-code", resp.reason_phrase)
    return f"{resp.status_code} {code}"


@mcp.tool()
def list_files(container: str, ctx: Context) -> str:
    """List the file names in a Lindhav storage container."""
    token = get_token(ctx)
    if not token:
        return "No bearer token received, so nothing was sent to storage."
    resp = call_storage(token, f"{quote(container)}?restype=container&comp=list")
    if resp.status_code != 200:
        return storage_error(resp)
    names = [n.text for n in ET.fromstring(resp.content).iter("Name") if n.text]
    return "\n".join(names) if names else "The container is empty."


@mcp.tool()
def read_file(container: str, name: str, ctx: Context) -> str:
    """Read one text file from a Lindhav storage container."""
    token = get_token(ctx)
    if not token:
        return "No bearer token received, so nothing was sent to storage."
    resp = call_storage(token, f"{quote(container)}/{quote(name)}")
    if resp.status_code != 200:
        return storage_error(resp)
    return resp.text


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
