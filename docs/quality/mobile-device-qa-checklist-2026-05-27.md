# Mobile Device QA Checklist - 2026-05-27

## Conclusion

Automated simulator/emulator evidence is strong, but the final mobile release gate still requires physical-device and assistive-technology evidence. This checklist records the exact checks needed to close that gap.

Current device evidence: iPhone 17 Simulator is available; `sky的iPhone 12` is visible only as a wireless device, so it is not accepted as physical Flutter integration-test evidence.

## Preflight

Run from the repository root:

```bash
./scripts/check-mobile-device-qa-preflight.sh
```

Require a USB-connected iPhone:

```bash
REQUIRE_PHYSICAL_IOS=1 ./scripts/check-mobile-device-qa-preflight.sh
```

Run real-backend E2E on a USB-connected iPhone:

```bash
REQUIRE_PHYSICAL_IOS=1 \
RUN_PHYSICAL_IOS_E2E=1 \
IOS_PHYSICAL_DEVICE_ID=<device-id> \
./scripts/check-mobile-device-qa-preflight.sh
```

## Physical Device Evidence

| Item | Required Evidence | Status | Evidence |
| --- | --- | --- | --- |
| Device identity | Physical device model, OS version, device ID, and connection type | PENDING |  |
| Build identity | App version, build number, and artifact/source used for install | PENDING |  |
| USB iPhone preflight | `REQUIRE_PHYSICAL_IOS=1 ./scripts/check-mobile-device-qa-preflight.sh` passes | PENDING |  |
| Physical iPhone E2E | USB-connected iPhone E2E or signed-install manual result is recorded | PENDING |  |

## Manual Physical Device Checklist

| Area | Required Result | Status | Evidence |
| --- | --- | --- | --- |
| Install/launch | App installs and launches on physical iPhone without signing/runtime error | PENDING | Device ID, iOS version, build number |
| Login/setup | Server address, first password, login, and token persistence work | PENDING | Short notes or screenshot |
| Home | Premium dashboard, family summary, and budget surfaces render without overflow | PENDING | Light/dark screenshots |
| Quick transaction | Keyboard does not cover save action; amount/category/member/account fields work | PENDING | Test transaction ID or screenshot |
| Family Hub | Member list, default member, disabled member, and summary totals are readable | PENDING | Screenshot |
| AI Reports | Empty, generating, completed, failed, and expanded states are readable; no raw API key appears | PENDING | Screenshot or notes |
| Safe area | Notch, dynamic island/status bar, bottom home indicator, and landscape/rotation behavior are acceptable | PENDING | Screenshot |
| Performance | Opening quick transaction and expanding AI reports feel smooth; no continuous decorative animation stutter | PENDING | Device/version notes |
| Reduced motion | With platform reduced motion enabled, animations do not become distracting | PENDING | PASS/FAIL notes |

## Assistive Technology Checklist

| Platform | Check | Required Result |
| --- | --- | --- |
| iOS VoiceOver | Traverse Home, Quick Transaction, AI Reports, Family Hub | Controls announce meaningful labels and order |
| iOS VoiceOver | Create a transaction | Text fields and submit state are understandable |
| Android TalkBack | Traverse Home, Quick Transaction, AI Reports, Family Hub | Controls announce meaningful labels and order |
| Android TalkBack | Create a transaction | Text fields and submit state are understandable |

## Release Decision

Do not mark physical mobile QA complete until every row above is changed from `PENDING` to `PASS` or a documented non-blocking exception, and the checklist records:

- device model and OS version;
- build version/build number;
- physical iPhone E2E result or explicit signed-install manual result;
- VoiceOver/TalkBack result if public accessibility is a release criterion;
- screenshots or notes for any failed item.
