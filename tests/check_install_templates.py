from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INSTALL_SH = ROOT / "install.sh"


def read_install_script() -> str:
    return INSTALL_SH.read_text(encoding="utf-8")


def assert_contains(text: str, needle: str, message: str) -> None:
    assert needle in text, message


def assert_not_contains(text: str, needle: str, message: str) -> None:
    assert needle not in text, message


def main() -> None:
    text = read_install_script()

    assert_contains(
        text,
        '[ "$INTERFACE" = "wan" ] && [ "$ACTION" = "ifup" ]',
        "mwan3.user should use mwan3 event environment variables",
    )
    assert_not_contains(
        text,
        '[ "$1" = "wan" ] && [ "$2" = "connected" ]',
        "mwan3.user should not use obsolete positional arguments",
    )
    assert_contains(
        text,
        "/root/campus_auth.sh hook >/dev/null 2>&1 &",
        "mwan3 hook should not duplicate script logs into LOG_FILE",
    )

    assert_contains(
        text,
        'if do_auth; then\n                send_dingtalk "',
        "morning schedule should branch on do_auth success",
    )
    assert_contains(
        text,
        "local rc=$?",
        "morning schedule should preserve the failed auth exit code",
    )
    assert_contains(
        text,
        "local status=$(check_need_auth)",
        "morning schedule should include current auth status in failure notices",
    )

    assert_contains(
        text,
        'if [ -s /etc/config/mwan3 ]; then',
        "installer should not overwrite an existing mwan3 config unconditionally",
    )
    assert_contains(
        text,
        'cp -a /etc/config/mwan3 "/etc/config/mwan3.bak-campus_auth-$(date +%Y%m%d%H%M%S)"',
        "installer should back up existing mwan3 config before skipping it",
    )

    assert_not_contains(
        text,
        ">> /var/log/campus_auth.log 2>&1",
        "scheduled/hook callers should not append to LOG_FILE because campus_auth.sh logs itself",
    )
    assert_contains(
        text,
        "*/30 * * * * /root/campus_auth.sh hook >/dev/null 2>&1",
        "cron health check should discard wrapper output",
    )

    assert_contains(
        text,
        "option auth_poll_max '20'",
        "default config should expose the portal dial-result polling count",
    )
    assert_contains(
        text,
        "getAuthResult.do",
        "auth script should poll the portal dial-result endpoint after pending login",
    )
    assert_contains(
        text,
        "正在进行外网",
        "auth script should recognize the portal pending external-dial state",
    )
    assert_contains(
        text,
        "sanitize_auth_text",
        "auth script should redact sensitive portal fields before logging response snippets",
    )
    assert_contains(
        text,
        "get_portal_url_parameter",
        "auth script should capture the BRAS redirect query for the login POST",
    )
    assert_contains(
        text,
        'auth_url="${auth_url}?${url_parameter}"',
        "auth script should submit to webauth.do with the portal urlParameter query",
    )
    assert_contains(
        text,
        '--data-urlencode "passwd=${PASSWORD}"',
        "auth script should URL-encode credentials in form submissions",
    )


if __name__ == "__main__":
    main()
