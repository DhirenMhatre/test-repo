# License Scanner Test Repository

This repository contains comprehensive test cases for the Codity.ai license compliance scanner across all 5 supported ecosystems.

## Purpose

Test the license scanner's ability to:
1. ✅ **Detect HIGH risk licenses** (GPL, LGPL, AGPL) - Strong copyleft
2. ✅ **Detect MEDIUM risk licenses** (EPL, MPL, EUPL) - Weak copyleft
3. ✅ **Detect LOW risk licenses** (MIT, Apache, BSD, ISC, PSF, Ruby, CC0) - Permissive
4. ✅ **Handle dual licenses** (Apache-2.0 OR BSD-3-Clause)
5. ✅ **Normalize license strings** ("MIT License" → "MIT", "Apache Software License" → "Apache-2.0")
6. ✅ **Flag UNKNOWN licenses** (packages without clear licensing)

## Test Coverage by Ecosystem

### 🐍 Python (PyPI) - `python-service/requirements.txt`

| Risk Level | License Type | Example Packages | Count |
|-----------|--------------|------------------|-------|
| 🔴 **HIGH** | GPL-3.0 | unrar | 1 |
| 🔴 **HIGH** | LGPL-2.1 | chardet, pygpgme | 2 |
| 🟡 **MEDIUM** | MPL-2.0 | certifi | 1 |
| 🟢 **LOW** | MIT | flask, requests, pytest, black, mypy, etc. | ~15 |
| 🟢 **LOW** | Apache-2.0 | boto3, urllib3 | 2 |
| 🟢 **LOW** | BSD-3-Clause | numpy, pandas, django, werkzeug | 4 |
| 🟢 **LOW** | Python-2.0 (PSF) | matplotlib | 1 |
| 🟢 **LOW** | Apache-2.0 OR BSD-3-Clause | cryptography | 1 |
| 🟢 **LOW** | CC0-1.0 | spdx-license-ids | 1 |
| ❓ **UNKNOWN** | N/A | gpl-license-checker | 1 |

**Total Python packages:** ~29

### ☕ Java (Maven) - `java-service/pom.xml`

| Risk Level | License Type | Example Packages | Count |
|-----------|--------------|------------------|-------|
| 🟡 **MEDIUM** | EPL-2.0 | junit-jupiter | 1 |
| 🟡 **MEDIUM** | EPL-1.0 | logback-classic | 1 |
| 🟢 **LOW** | Apache-2.0 | Spring Boot, Jackson, Guava, Commons, Log4j | ~10 |
| 🟢 **LOW** | MIT | SLF4J, Mockito, Lombok | ~3 |
| 🟢 **LOW** | BSD-2-Clause | PostgreSQL driver | 1 |

**Total Java packages:** ~16

### 🌐 JavaScript (NPM) - `js-service/package.json`

| Risk Level | License Type | Example Packages | Count |
|-----------|--------------|------------------|-------|
| 🟢 **LOW** | MIT | express, lodash, axios, dotenv, etc. | ~10 |
| 🟢 **LOW** | Apache-2.0 | (if present) | TBD |

**Total NPM packages:** ~10

### 💎 Ruby (RubyGems) - `ruby-service/Gemfile`

| Risk Level | License Type | Example Packages | Count |
|-----------|--------------|------------------|-------|
| 🟢 **LOW** | MIT | rails, rspec, etc. | ~10 |
| 🟢 **LOW** | Ruby | ruby stdlib packages | ~5 |

**Total Ruby packages:** ~15

### 🐹 Go (Go modules) - `go-service/go.mod`

| Risk Level | License Type | Example Packages | Count |
|-----------|--------------|------------------|-------|
| 🟢 **LOW** | MIT | gin, testify, viper, etc. | ~10 |
| 🟢 **LOW** | BSD-3-Clause | golang.org/x/*, google.golang.org/* | ~5 |
| 🟢 **LOW** | Apache-2.0 | cobra, sonic | ~2 |

**Total Go packages:** ~17

## Expected Scan Results

### Summary Metrics:
- **Packages Scanned:** ~87
- **High Risk (Copyleft):** 3 (unrar, chardet, pygpgme)
- **Medium Risk (Weak Copyleft):** 3 (certifi, junit-jupiter, logback-classic)
- **Low Risk (Permissive):** ~80
- **Unknown License:** 1 (gpl-license-checker)

### Risk Distribution:
```
HIGH:    3.4% (3/87)   - Strong copyleft (GPL, LGPL)
MEDIUM:  3.4% (3/87)   - Weak copyleft (EPL, MPL)
LOW:    92.0% (80/87)  - Permissive (MIT, Apache, BSD, etc.)
UNKNOWN: 1.2% (1/87)   - No license info
```

## License Normalization Tests

The scanner should correctly normalize these license string variations:

| Raw String from Package Manager | Normalized SPDX ID | Risk |
|---------------------------------|-------------------|------|
| "MIT License" | MIT | LOW |
| "Apache Software License" | Apache-2.0 | LOW |
| "Apache 2.0" | Apache-2.0 | LOW |
| "BSD License" | BSD-3-Clause | LOW |
| "GNU Lesser General Public License v2 or later (LGPLv2+)" | LGPL-2.1-or-later | HIGH |
| "GNU Library or Lesser General Public License (LGPL)" | LGPL-2.1-only | HIGH |
| "Python Software Foundation License" | Python-2.0 | LOW |
| "PSF-2.0" | Python-2.0 | LOW |
| "Ruby" | Ruby | LOW |
| "Mozilla Public License 2.0" | MPL-2.0 | MEDIUM |
| "Eclipse Public License 2.0" | EPL-2.0 | MEDIUM |
| "Apache-2.0 OR BSD-3-Clause" | Apache-2.0 OR BSD-3-Clause | LOW |
| "CC0-1.0" | CC0-1.0 | LOW |

## Verification Commands

### Run License Scan:
```bash
cd /home/dhiren-mhatre/codity/test-repo
git checkout feature/test-license-scanning
# Trigger scan via PR or CI
```

### Verify Results:
Expected output should show:
- ✅ 3 HIGH risk packages (GPL/LGPL)
- ✅ 3 MEDIUM risk packages (EPL/MPL)
- ✅ ~80 LOW risk packages (MIT/Apache/BSD/etc.)
- ✅ 1 UNKNOWN package
- ✅ NO false positives (MIT shown as MEDIUM, etc.)

### Test Individual Packages:
```python
from security_scanner.license_normalizer import normalize_license_string
from security_scanner.spdx_license_db import get_license_risk

# Test cases
tests = [
    ("chardet", "LGPL-2.1-only", "HIGH"),
    ("certifi", "MPL-2.0", "MEDIUM"),
    ("flask", "MIT", "LOW"),
    ("junit-jupiter", "EPL-2.0", "MEDIUM"),
]

for pkg, expected_license, expected_risk in tests:
    print(f"Testing {pkg}: {expected_license} → {expected_risk}")
```

## False Positive Prevention

This test repo specifically guards against previously detected false positives:

### ❌ **Before Fixes (WRONG):**
- MIT License → MEDIUM (should be LOW)
- Apache Software License → MEDIUM (should be LOW)
- Ruby → MEDIUM (should be LOW)
- CC0-1.0 → MEDIUM (should be LOW)
- PSF-2.0 → MEDIUM (should be LOW)

### ✅ **After Fixes (CORRECT):**
- MIT License → LOW ✓
- Apache Software License → LOW ✓
- Ruby → LOW ✓
- CC0-1.0 → LOW ✓
- PSF-2.0 → LOW ✓

## References

- [SPDX License List](https://spdx.org/licenses/)
- [Choose a License](https://choosealicense.com/)
- [OSI Approved Licenses](https://opensource.org/licenses)
- [PyPI License Classifiers](https://pypi.org/search/?c=License)
- [Maven Central License Info](https://search.maven.org/)

## Testing Documentation

For complete documentation of license scanner fixes, see:
- [FALSE_POSITIVE_FIXES.md](/home/dhiren-mhatre/codity/codity.ai/FALSE_POSITIVE_FIXES.md)
- [LICENSE_SCANNER_FIXES.md](/home/dhiren-mhatre/codity/codity.ai/LICENSE_SCANNER_FIXES.md)
- [SPDX_LICENSE_SYSTEM.md](/home/dhiren-mhatre/codity/codity.ai/SPDX_LICENSE_SYSTEM.md)

---

**Last Updated:** 2026-01-20
**Branch:** `feature/test-license-scanning`
**Status:** ✅ Ready for Testing
