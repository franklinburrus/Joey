"""Bounded iCloud INBOX intake. Input is private stdin; output is sanitized JSON.

No flags, mailbox contents, credentials, authentication headers or message text
are written. This module also exposes a fake-mailbox seam for offline fixtures.
"""
import email.policy
from email.parser import BytesParser
from html.parser import HTMLParser
import hmac
import imaplib
import json
import re
import signal
import socket
import ssl
import sys
from urllib.parse import unquote, urlsplit

ALIAS = "uploadtojoey@icloud.com"
MAX_MESSAGE = 1024 * 1024
MAX_HEADERS = 65536
MAX_INPUT = 16384
HOSTS = {"youtube.com", "www.youtube.com", "youtu.be", "x.com", "www.x.com", "twitter.com"}
URL_PATTERN = re.compile(r"https?://[^\s<>\"']+", re.I)


def rejected(reason):
    return {"status": "rejected", "reason": reason, "links": []}


def addresses(msg, field):
    result = []
    for header in msg.get_all(field, []):
        if header.defects:
            raise ValueError("Malformed address")
        for address in header.addresses:
            if not address.username or not address.domain:
                raise ValueError("Incomplete address")
            result.append(address.addr_spec.lower())
    return result


def validate_headers(msg, allowed_senders):
    recipients = addresses(msg, "To") + addresses(msg, "Cc")
    if ALIAS not in recipients:
        return rejected("recipientMismatch")
    if len(msg.get_all("From", [])) != 1:
        return rejected("invalidSender")
    senders = addresses(msg, "From")
    if len(senders) != 1:
        return rejected("invalidSender")
    if senders[0] not in allowed_senders:
        return rejected("senderNotAllowed")
    return None


class BodyHTML(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.text, self.links, self.hidden = [], [], 0

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style", "template"}:
            self.hidden += 1
        if not self.hidden:
            if tag in {"br", "p", "div", "li"}:
                self.text.append("\n")
            if tag == "a":
                self.links.extend(value for key, value in attrs if key == "href" and value)

    def handle_endtag(self, tag):
        if tag in {"script", "style", "template"} and self.hidden:
            self.hidden -= 1
        if not self.hidden and tag in {"p", "div", "li"}:
            self.text.append("\n")

    def handle_data(self, data):
        if not self.hidden:
            self.text.append(data)


def body_part(msg):
    # Named files remain attachments even when a sender labels them "inline".
    # A mixed message's first eligible part owns its body; alternatives prefer
    # plain text. Related images and attached messages never become commands.
    if (msg.get_filename() is not None or msg.get_content_type() == "message/rfc822"
            or msg.get_content_disposition() == "attachment"):
        return None
    if msg.get_content_type() in {"text/plain", "text/html"}:
        return msg
    if not msg.is_multipart():
        return None
    parts = list(msg.iter_parts())
    if msg.get_content_type() == "multipart/related":
        start = msg.get_param("start")
        parts = [part for part in parts if part.get("Content-ID") == start] if start else parts[:1]
    bodies = [body for part in parts if (body := body_part(part)) is not None]
    if msg.get_content_type() == "multipart/alternative":
        return next((body for body in bodies if body.get_content_type() == "text/plain"), bodies[0] if bodies else None)
    return bodies[0] if bodies else None


def parse_message(raw, allowed_senders, token=None):
    if len(raw) > MAX_MESSAGE:
        return rejected("messageTooLarge")
    try:
        msg = BytesParser(policy=email.policy.default).parsebytes(raw)
        failure = validate_headers(msg, allowed_senders)
        if failure:
            return failure
        if any(part.defects for part in msg.walk()):
            return rejected("malformedMessage")
        body = body_part(msg)
        if body is None:
            return rejected("noSupportedLinks")
        content = body.get_content()
        if not isinstance(content, str):
            return rejected("malformedMessage")
        candidates = []
        if body.get_content_type() == "text/html":
            html = BodyHTML(); html.feed(content); html.close()
            content = "".join(html.text)
            candidates.extend(html.links)
        candidates.extend(URL_PATTERN.findall(content))
        links = []
        for candidate in candidates:
            candidate = candidate.rstrip(".,;!?)\u201d\u2019")
            if not all(32 < ord(char) < 127 for char in candidate):
                continue
            parsed = urlsplit(candidate)
            if (parsed.scheme != "https" or parsed.hostname not in HOSTS or
                    parsed.username is not None or parsed.password is not None or
                    parsed.port not in (None, 443) or len(candidate) > 2048):
                continue
            # Never let the template secret escape via a pasted URL, including
            # percent-encoded query text. Swift canonicalizes the source later.
            if token and (token in candidate or token in unquote(unquote(candidate))):
                return rejected("secretInLink")
            if candidate not in links:
                links.append(candidate)
            if len(links) > 100:
                return rejected("tooManyLinks")
        if not links:
            return rejected("noSupportedLinks")
        tokens = re.findall(r"(?mi)^\s*Joey-Token:[ \t]*([^\r\n]*)", content)
        authorized = (isinstance(token, str) and len(token) >= 43 and len(tokens) == 1
                      and hmac.compare_digest(tokens[0].strip(), token))
        return {"status": "authorized" if authorized else "pendingAuthorization",
                "reason": "templateToken" if authorized else (
                    "intakeTokenMissingOrInvalid" if token else "senderAuthenticationUnavailable"),
                "links": links}
    except (ValueError, TypeError, LookupError, UnicodeError, AttributeError, RecursionError):
        return rejected("malformedMessage")


def mailbox_numbers(client):
    values = []
    for name in ("UIDVALIDITY", "UIDNEXT"):
        data = client.response(name)[1]
        if not data or not data[0] or not data[0].isdigit():
            raise ValueError("Missing mailbox identity")
        value = int(data[0])
        if not 0 < value <= 4294967295:
            raise ValueError("Invalid mailbox identity")
        values.append(value)
    return values


def fetched(client, uid, expression, limit):
    status, parts = client.uid("fetch", str(uid), expression)
    if status != "OK":
        raise OSError("Fetch unavailable")
    literals = [part for part in parts if isinstance(part, tuple)]
    if len(literals) != 1 or len(literals[0][1]) > limit:
        raise ValueError("Invalid fetch response")
    meta, raw = literals[0]
    matched = re.search(rb"\bUID (\d+)\b", meta)
    size = re.search(rb"\bRFC822.SIZE (\d+)\b", meta)
    if not matched or int(matched[1]) != uid or not size:
        raise ValueError("Fetch identity mismatch")
    return raw, int(size[1])


def scan(client, request):
    validity, next_uid = mailbox_numbers(client)
    if request["uidValidity"] != validity:
        return {"error": "uidValidityChanged"}
    frontier = request["frontier"]
    result = {"uidValidity": validity, "uidNext": next_uid, "frontier": frontier, "messages": []}
    capacity = min(100, request.get("capacity", 0))
    upper = min(next_uid - 1, frontier + 1000)
    if upper <= frontier or capacity <= 0:
        return result
    status, data = client.uid("search", None, "UID", f"{frontier + 1}:{upper}",
                              "OR", "TO", f'"{ALIAS}"', "CC", f'"{ALIAS}"')
    if status != "OK" or len(data) != 1 or not isinstance(data[0], bytes) or len(data[0]) > 12000:
        raise ValueError("Invalid search response")
    uids = sorted(set(int(value) for value in data[0].split()))
    uids = [uid for uid in uids if frontier < uid <= upper]
    processed = 0
    for uid in uids[:50]:
        headers, size = fetched(client, uid, f"(UID RFC822.SIZE BODY.PEEK[HEADER]<0.{MAX_HEADERS + 1}>)", MAX_HEADERS + 1)
        if len(headers) > MAX_HEADERS:
            item = rejected("headersTooLarge")
        else:
            try:
                msg = BytesParser(policy=email.policy.default).parsebytes(headers, headersonly=True)
                item = validate_headers(msg, request.get("allowedSenders", []))
            except (ValueError, AttributeError, RecursionError):
                item = rejected("malformedMessage")
            if item and item["reason"] == "recipientMismatch":
                result["frontier"] = uid; processed += 1
                continue
            if not item:
                if size > MAX_MESSAGE:
                    item = rejected("messageTooLarge")
                else:
                    raw, observed = fetched(client, uid, f"(UID RFC822.SIZE BODY.PEEK[]<0.{MAX_MESSAGE + 1}>)", MAX_MESSAGE + 1)
                    if observed != size or len(raw) != size:
                        raise ValueError("Incomplete body")
                    item = parse_message(raw, request.get("allowedSenders", []), request.get("token"))
        # Swift owns canonical-link limits and pending capacity. A rejected
        # oversized message must not obstruct the next small valid request.
        # Bound the response without acknowledging deferred server messages.
        entry = dict(item, uid=uid)
        if len(json.dumps(dict(result, messages=result["messages"] + [entry])).encode()) > 256 * 1024:
            break
        result["messages"].append(entry)
        result["frontier"] = uid; processed += 1
    if processed == len(uids):
        result["frontier"] = upper
    return result


def safe_scan(client, request):
    try:
        return scan(client, request)
    except (OSError, TimeoutError, imaplib.IMAP4.abort):
        return {"error": "networkUnavailable"}
    except Exception:
        return {"error": "invalidMailboxResponse"}


def run(request):
    client = None
    try:
        if (request.get("action") not in {"test", "baseline", "scan"} or
                not isinstance(request.get("account"), str) or not request["account"] or
                not isinstance(request.get("password"), str) or not request["password"]):
            return {"error": "invalidInput"}
        # Default context verifies both certificate chain and hostname.
        client = imaplib.IMAP4_SSL("imap.mail.me.com", 993, ssl_context=ssl.create_default_context(), timeout=15)
        client.debug = 0
        try:
            client.login(request["account"], request["password"])
        except imaplib.IMAP4.error:
            return {"error": "authenticationFailed"}
        status, _ = client.select("INBOX", readonly=True)
        if status != "OK":
            return {"error": "mailboxUnavailable"}
        if request["action"] == "scan":
            return safe_scan(client, request)
        validity, next_uid = mailbox_numbers(client)
        return {"uidValidity": validity, "uidNext": next_uid, "frontier": next_uid - 1, "messages": []}
    except (OSError, TimeoutError, imaplib.IMAP4.abort):
        return {"error": "networkUnavailable"}
    except Exception:
        return {"error": "invalidMailboxResponse"}
    finally:
        if client is not None:
            try:
                client.logout()  # No CLOSE/EXPUNGE/STORE/MOVE/DELETE command.
            except Exception:
                pass


def deadline(_signal, _frame):
    raise TimeoutError("Deadline")


def main():
    signal.signal(signal.SIGALRM, deadline)
    signal.setitimer(signal.ITIMER_REAL, 60)
    try:
        data = sys.stdin.buffer.read(MAX_INPUT + 1)
        request = json.loads(data) if len(data) <= MAX_INPUT else None
        result = run(request) if isinstance(request, dict) else {"error": "invalidInput"}
    except Exception:
        result = {"error": "invalidInput"}
    signal.setitimer(signal.ITIMER_REAL, 0)
    sys.stdout.write(json.dumps(result, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
