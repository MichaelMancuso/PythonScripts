# Summary — SMC Print Relay Retest & Report Updates

**Subject:** SMC Print Relay Retest Results + Report Updates

Hi [Name],

Here's a summary of the work completed across the two engagements.

---

## 1. SMC Print Relay — Remediation Retest (v1.0.05 → v1.0.0.7)

I retested the SMC Print Relay against the 11 findings from the June assessment, using the new V7 installer build (host binary **v1.0.0.7**, installer dated 07/21/2026). As in the original engagement, verification was performed **statically against the application binary**: I extracted the MSI payload, decompiled the host binary (`DesktopPrintRelayService.Host.exe`) from IL, verified Authenticode signatures, and checked the versions of the bundled components. The retest was performed on 07/23/2026.

**Result: 6 findings fully remediated, 2 partially remediated, 3 still open.**

**The critical remote attack chain is broken.** The permissive CORS delivery vector (Finding 4) and all three authentication bypasses (Findings 1, 2, 3) are closed, so an unauthenticated web page can no longer drive the relay to print. Because the print, routing-map, and read endpoints now all require a validated token, the two Medium unauthenticated-access findings (5, 6) and the SSRF (Finding 8) are closed as well.

### Status by finding

| # | Finding | Severity | Retest Status |
|---|---------|----------|---------------|
| 1 | Auth bypass via attacker-controlled token introspection URL | High | **Partially Fixed** — attacker URL now blocked by a host allowlist; residual: the token `active` claim is still not checked |
| 2 | Auth bypass via attacker-controlled OIDC discovery (B2C) | High | **Fixed** |
| 3 | Missing authorization on the PrintPdf endpoint | High | **Fixed** |
| 4 | Overly permissive CORS policy | High | **Fixed** |
| 5 | Unauthenticated modification of the print-routing map | Medium | **Fixed** |
| 6 | Unauthenticated printer enumeration | Medium | **Fixed** |
| 7 | End-of-life & outdated components | Medium | **Partially Fixed** — Newtonsoft.Json upgraded; still on EOL ASP.NET Core 2.x and Aspose.PDF 20.10 (2020) |
| 8 | Constrained SSRF via X-ProviderValidationUrl | Low | **Fixed** |
| 9 | Unsigned application binaries and installer | Low | **Not Fixed** |
| 10 | Over-permissive HTTP URL ACL (Everyone) | Low | **Not Fixed** |
| 11 | Local persistence & configuration hygiene | Info | **Not Fixed** |

### Remaining work for a clean retest
- **F1:** enforce `active == true` in the Okta introspection response check.
- **F7:** re-platform off end-of-life ASP.NET Core 2.x and upgrade or sandbox Aspose.PDF (still the 2020-era 20.10 build).
- **F9:** Authenticode-sign all three artifacts (`setup.exe`, the MSI, and the host `.exe`).
- **F10:** remove the `netsh … user=everyone` URL ACL.
- **F11:** harden the HKCU-based configuration/persistence defaults (`SecureVersion=False`, autostart/port/origins read from a user-writable hive).

### Deliverables
- **Retest Results section** added to the existing penetration test report (status summary table + per-finding evidence).
- **Standalone Retest report (`RETEST.docx`)** in the Inovalon template format, containing:
  - Executive summary and a full retest status table
  - **Remediations Verified** — Findings 1–8, each with the decompiled code evidence confirming the fix
  - **Findings Remaining** — the 5 open items in the standard finding format, including annotated code/CLI **evidence snapshots** for Findings 1 and 7

---

## 2. MyShare Penetration Test Report — Production & Formatting

- Reformatted the draft to the Inovalon template (cover page, styled headings, working table of contents, header/footer, and properly structured tables).
- Added two findings (**F-003** and **F-004**, broken object-level authorization) from the source notes.
- Reordered the findings so the three High findings precede the Medium, and renumbered throughout.
- Fixed a template footer bug that was clipping two-digit page numbers.

---

## Note on the Word files
All Word documents are set to refresh fields on open — accepting the **"update fields"** prompt in Word locks the table-of-contents page numbers to the final layout.

Happy to walk through any of this.

Thanks,
Michael
