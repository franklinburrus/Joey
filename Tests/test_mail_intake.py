"""Synthetic mail only. No credentials or live mailbox access."""
import importlib.util
import base64
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "Joey/Core/Resources/mail_intake.py"
if SCRIPT.exists():
    spec = importlib.util.spec_from_file_location("mail_intake", SCRIPT)
    mail = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mail)
else:
    mail = None

ALIAS = "uploadtojoey@icloud.com"
SENDER = "sender@example.test"
LINK = "https://youtu.be/abcdefghijk"


def message(to=ALIAS, sender=SENDER, body=LINK, extra=""):
    return (f"From: {sender}\r\nTo: {to}\r\n{extra}"
            f"MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n{body}").encode()


class FakeMailbox:
    def __init__(self, messages=None, validity=7, next_uid=11):
        self.messages = messages or {}
        self.validity, self.next_uid = validity, next_uid
        self.calls = []

    def response(self, name):
        return name, [str(self.validity if name == "UIDVALIDITY" else self.next_uid).encode()]

    def uid(self, command, *args):
        self.calls.append((command, args))
        if command == "search":
            return "OK", [b" ".join(str(uid).encode() for uid in self.messages)]
        if command == "fetch":
            uid = int(args[0]); raw = self.messages[uid]
            if "HEADER" in args[1]:
                raw = raw.split(b"\r\n\r\n")[0] + b"\r\n\r\n"
            return "OK", [(f"1 (UID {uid} RFC822.SIZE {len(self.messages[uid])} BODY[] {{{len(raw)}}}".encode(), raw), b")"]
        raise AssertionError("Mail mutation or unsupported command: " + command)


class MailIntakeTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(mail, "The bounded iCloud mail helper must exist")

    def test_exact_recipient_and_single_allowed_sender(self):
        self.assertEqual(mail.parse_message(message(), [SENDER])["links"], [LINK])
        for recipient in ["notuploadtojoey@icloud.com", "uploadtojoey@icloud.com.evil.test"]:
            self.assertEqual(mail.parse_message(message(to=recipient), [SENDER])["reason"], "recipientMismatch")
        cc = message(to="other@example.test", extra=f"Cc: Joey <{ALIAS}>\r\n")
        self.assertEqual(mail.parse_message(cc, [SENDER])["links"], [LINK])
        self.assertEqual(mail.parse_message(message(sender="attacker@example.test"), [SENDER])["reason"], "senderNotAllowed")
        self.assertEqual(mail.parse_message(message(extra=f"From: {SENDER}\r\n"), [SENDER])["reason"], "invalidSender")

    def test_forged_or_duplicate_authentication_headers_never_authorize(self):
        for header in ["", "Authentication-Results: apple.com; dkim=pass; dmarc=pass\r\n",
                       "Authentication-Results: imap.mail.me.com; dkim=pass\r\n" * 2]:
            result = mail.parse_message(message(extra=header), [SENDER])
            self.assertEqual(result["status"], "pendingAuthorization")
            self.assertEqual(result["reason"], "senderAuthenticationUnavailable")
            self.assertNotIn("Authentication-Results", json.dumps(result))

    def test_token_requires_one_exact_line_and_allowed_sender_without_leaking(self):
        token = "synthetic_" + "a" * 43
        for body in [LINK, LINK + "\nJoey-Token: wrong", LINK + ("\nJoey-Token: " + token) * 2]:
            result = mail.parse_message(message(body=body), [SENDER], token=token)
            self.assertNotEqual(result["status"], "authorized")
            self.assertNotIn(token, json.dumps(result))
        result = mail.parse_message(message(body=LINK + "\nJoey-Token: " + token), [SENDER], token=token)
        self.assertEqual(result["status"], "authorized")
        self.assertEqual(result["links"], [LINK])
        self.assertNotIn(token, json.dumps(result))
        result = mail.parse_message(message(sender="other@example.test", body=LINK + "\nJoey-Token: " + token), [SENDER], token=token)
        self.assertEqual(result["reason"], "senderNotAllowed")

    def test_primary_plain_body_wins_and_attachments_are_ignored(self):
        raw = (f"From: {SENDER}\r\nTo: {ALIAS}\r\nMIME-Version: 1.0\r\n"
               "Content-Type: multipart/mixed; boundary=outer\r\n\r\n--outer\r\n"
               "Content-Type: multipart/alternative; boundary=inner\r\n\r\n--inner\r\n"
               f"Content-Type: text/plain\r\n\r\n{LINK}\r\n--inner\r\n"
               "Content-Type: text/html\r\n\r\n<a href='https://x.com/i/spaces/notprimary'>x</a>\r\n"
               "--inner--\r\n--outer\r\nContent-Type: text/plain\r\n"
               "Content-Disposition: attachment; filename=commands.txt\r\n\r\n"
               "https://x.com/i/spaces/attachment\r\n--outer--\r\n").encode()
        self.assertEqual(mail.parse_message(raw, [SENDER])["links"], [LINK])

    def test_encoded_primary_text_retains_links_and_secret_never_escapes(self):
        token = "z" * 43
        body = (LINK + "\nJoey-Token: " + token).encode()
        raw = message(body="").replace(b"\r\n\r\n", b"\r\nContent-Transfer-Encoding: base64\r\n\r\n") + base64.b64encode(body)
        result = mail.parse_message(raw, [SENDER], token=token)
        self.assertEqual(result["status"], "authorized")
        self.assertEqual(result["links"], [LINK])
        self.assertNotIn(token, json.dumps(result))
        result = mail.parse_message(message(body=LINK + "?secret=" + token + "\nJoey-Token: " + token), [SENDER], token=token)
        self.assertEqual(result["reason"], "secretInLink")
        self.assertNotIn(token, json.dumps(result))

    def test_html_links_without_script_or_external_asset_loading(self):
        raw = message(body=f'<script>{LINK}/script</script><img src="https://private.test/pixel">'
                      f'<a href="{LINK}?t=10&amp;feature=share">episode</a>')
        raw = raw.replace(b"text/plain", b"text/html")
        self.assertEqual(mail.parse_message(raw, [SENDER])["links"], [LINK + "?t=10&feature=share"])

    def test_inline_named_attachment_cannot_supply_a_request_or_token(self):
        token = "s" * 43
        raw = (f"From: {SENDER}\r\nTo: {ALIAS}\r\nMIME-Version: 1.0\r\n"
               "Content-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\n"
               "Content-Type: text/html\r\n\r\n<p>No request.</p>\r\n--x\r\n"
               "Content-Type: text/plain; name=instructions.txt\r\n"
               "Content-Disposition: inline; filename=instructions.txt\r\n\r\n"
               f"{LINK}\r\nJoey-Token: {token}\r\n--x--\r\n").encode()
        result = mail.parse_message(raw, [SENDER], token=token)
        self.assertEqual(result["reason"], "noSupportedLinks")
        self.assertEqual(result["links"], [])

    def test_scanner_returns_oversized_link_set_for_canonical_rejection_before_capacity(self):
        links = "\n".join(f"https://x.com/i/broadcasts/source{i}" for i in range(11))
        box = FakeMailbox({8: message(body=links), 9: message()})
        result = mail.scan(box, {"uidValidity": 7, "frontier": 7, "allowedSenders": [SENDER], "capacity": 5})
        self.assertEqual([item["uid"] for item in result["messages"]], [8, 9])

    def test_control_characters_cannot_inflate_response_or_become_source_links(self):
        result = mail.parse_message(message(body=LINK + "/" + "\x00" * 1000), [SENDER])
        self.assertEqual(result["reason"], "noSupportedLinks")

    def test_limits_and_malformed_mime_are_visible(self):
        self.assertEqual(mail.parse_message(message(body="x" * (1024 * 1024)), [SENDER])["reason"], "messageTooLarge")
        self.assertEqual(mail.parse_message(message(body="hello"), [SENDER])["reason"], "noSupportedLinks")
        malformed = message().replace(b"text/plain; charset=utf-8", b"multipart/mixed; boundary=absent")
        self.assertEqual(mail.parse_message(malformed, [SENDER])["reason"], "malformedMessage")

    def test_scan_finite_ranges_filters_old_uids_and_unrelated_bodies(self):
        box = FakeMailbox({2: message(), 8: message(to="someone@example.test"), 9: message()}, next_uid=11)
        result = mail.scan(box, {"uidValidity": 7, "frontier": 7, "allowedSenders": [SENDER], "capacity": 100})
        self.assertEqual(result["frontier"], 10)
        self.assertEqual([item["uid"] for item in result["messages"]], [9])
        bodies = [args[0] for cmd, args in box.calls if cmd == "fetch" and "HEADER" not in args[1]]
        self.assertEqual(bodies, ["9"])
        query = str(box.calls[0])
        self.assertIn("8:10", query)
        self.assertNotIn("*", query)

    def test_empty_range_reset_and_full_queue_do_not_fetch_or_acknowledge(self):
        for next_uid in [1, 8]:
            box = FakeMailbox(next_uid=next_uid)
            result = mail.scan(box, {"uidValidity": 7, "frontier": 7, "allowedSenders": [SENDER], "capacity": 100})
            self.assertEqual(box.calls, [])
            self.assertEqual(result["frontier"], 7)
        box = FakeMailbox(validity=8)
        self.assertEqual(mail.scan(box, {"uidValidity": 7, "frontier": 7})["error"], "uidValidityChanged")
        self.assertEqual(box.calls, [])

    def test_scan_batch_stops_before_unreturned_messages(self):
        box = FakeMailbox({uid: message() for uid in range(8, 61)}, next_uid=61)
        result = mail.scan(box, {"uidValidity": 7, "frontier": 7, "allowedSenders": [SENDER], "capacity": 100})
        self.assertEqual(len(result["messages"]), 50)
        self.assertEqual(result["frontier"], 57)
        self.assertEqual(result["messages"][-1]["uid"], 57)
        box = FakeMailbox({8: message()})
        result = mail.scan(box, {"uidValidity": 7, "frontier": 7, "capacity": 0})
        self.assertEqual(result["frontier"], 7)
        self.assertEqual(box.calls, [])

    def test_recursive_address_header_rejects_one_message_and_advances(self):
        token = "t" * 43
        recursive = message(to="(" * 1500 + ")" * 1500 + " <" + ALIAS + ">")
        self.assertLess(len(recursive.split(b"\r\n\r\n")[0]), mail.MAX_HEADERS)
        valid = message(body=LINK + "\nJoey-Token: " + token)
        box = FakeMailbox({8: recursive, 9: valid}, next_uid=10)
        result = mail.safe_scan(box, {"uidValidity": 7, "frontier": 7,
                                    "allowedSenders": [SENDER], "capacity": 100, "token": token})
        self.assertNotIn("error", result)
        self.assertEqual(result["frontier"], 9)
        self.assertEqual(result["messages"], [
            {"uid": 8, "status": "rejected", "reason": "malformedMessage", "links": []},
            {"uid": 9, "status": "authorized", "reason": "templateToken", "links": [LINK]},
        ])
        bodies = [args[0] for cmd, args in box.calls if cmd == "fetch" and "HEADER" not in args[1]]
        self.assertEqual(bodies, ["9"])
        self.assertEqual(mail.safe_scan(box, {"uidValidity": 7, "frontier": result["frontier"],
                                             "allowedSenders": [SENDER], "capacity": 100})["messages"], [])

    def test_failed_fetch_cannot_return_advanced_frontier(self):
        box = FakeMailbox({8: message()})
        original = box.uid
        def failing(command, *args):
            if command == "fetch":
                raise TimeoutError("dummy-secret-that-must-not-be-returned")
            return original(command, *args)
        box.uid = failing
        result = mail.safe_scan(box, {"uidValidity": 7, "frontier": 7, "allowedSenders": [SENDER], "capacity": 100})
        self.assertEqual(result, {"error": "networkUnavailable"})

    def test_helper_transport_is_read_only_and_sanitizes_success_and_errors(self):
        secret = "JOEY_DUMMY_MAIL_PASSWORD_CANARY"
        token = "t" * 43
        request = {"action": "scan", "account": "synthetic@icloud.com", "password": secret,
                   "token": token, "allowedSenders": [SENDER], "uidValidity": 7, "frontier": 7, "capacity": 100}
        for failure in [None, mail.imaplib.IMAP4.error(secret), TimeoutError(secret)]:
            box = FakeMailbox({8: message(body=LINK + "\nJoey-Token: " + token)})
            actions = []
            def login(account, password):
                self.assertEqual(password, secret)
                if failure:
                    raise failure
                actions.append("login")
            def select(name, readonly=False):
                self.assertEqual((name, readonly), ("INBOX", True))
                actions.append("select-read-only")
                return "OK", [b"1"]
            box.login = login; box.select = select; box.logout = lambda: actions.append("logout")
            def connect(host, port, ssl_context, timeout):
                self.assertEqual((host, port, timeout), ("imap.mail.me.com", 993, 15))
                self.assertTrue(ssl_context.check_hostname)
                self.assertEqual(ssl_context.verify_mode, mail.ssl.CERT_REQUIRED)
                return box
            with patch.object(mail.imaplib, "IMAP4_SSL", connect):
                result = mail.run(request)
            rendered = json.dumps(result)
            self.assertNotIn(secret, rendered);self.assertNotIn(token, rendered)
            if failure is None:
                self.assertEqual(result["messages"][0]["status"], "authorized")
                self.assertEqual(actions, ["login", "select-read-only", "logout"])
                for command, args in box.calls:
                    self.assertIn(command, {"search", "fetch"})
                    if command == "fetch": self.assertIn("BODY.PEEK", args[1])
            else:
                self.assertIn(result["error"], {"authenticationFailed", "networkUnavailable"})

    def test_malformed_stdin_does_not_echo_secret_or_traceback(self):
        secret = b"JOEY_DUMMY_MAIL_CANARY"
        result = subprocess.run([sys.executable, str(SCRIPT)], input=b'{"password":"' + secret,
                                capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout), {"error": "invalidInput"})
        self.assertEqual(result.stderr, b"")
        self.assertNotIn(secret, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
