#!/usr/bin/env python3
"""Tests for the graphical installer's logic (installer/luna_installer/
backend.py): reading install.sh --probe, the checks it shares with
install.sh, the answers file (sourced by a real sh here), and progress.

    python3 tests/installer-test.py

Runs anywhere with Python 3; Qt is not needed.
"""
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "..", "installer"))

from luna_installer import backend, demo  # noqa: E402


class Probe(unittest.TestCase):
    def setUp(self):
        self.p = backend.parse_probe(demo.PROBE)

    def test_disks(self):
        names = [d["name"] for d in self.p["disks"]]
        self.assertEqual(names, ["nda0", "da0"])
        nvme = self.p["disks"][0]
        self.assertEqual(nvme["gb"], 1000)
        self.assertEqual(nvme["free_gb"], 238)
        self.assertTrue(nvme["alongside"])
        self.assertTrue(nvme["windows"])
        self.assertEqual(nvme["contents"], "Windows/data (2) EFI")   # trailing space gone
        usb = self.p["disks"][1]
        self.assertTrue(usb["removable"])
        self.assertFalse(usb["alongside"])
        self.assertIn("EFI system partition", usb["why"])

    def test_default_disk_is_never_usb(self):
        # the USB drive is bigger, but the built-in disk is preselected
        self.assertEqual(backend.default_disk(self.p["disks"]), "nda0")
        only_usb = [d for d in self.p["disks"] if d["removable"]]
        self.assertEqual(backend.default_disk(only_usb), "da0")
        self.assertEqual(backend.default_disk([]), "")
        tiny = [dict(self.p["disks"][0], name="vtbd1", gb=0, bytes=376832)]
        self.assertEqual(backend.default_disk(tiny, 30), "")

    def test_report_and_hw(self):
        self.assertEqual(self.p["hw"]["HW_BOOT"], "UEFI")
        self.assertEqual(self.p["hw"]["HW_DESKTOP_WHY"], "")
        statuses = {r["status"] for r in self.p["report"]}
        self.assertEqual(statuses, {"OK", "INFO", "WARN", "NO"})
        self.assertFalse(self.p["net"])
        self.assertEqual(self.p["min_gb"], 30)

    def test_boot_places(self):
        places = backend.boot_places(self.p["boot"]["nda0"], "LunaBSD")
        self.assertTrue(any("firmware boot menu" in x for x in places))
        self.assertTrue(any("Start Windows Boot Manager" in x for x in places))
        locked = backend.boot_places({"limine": "locked"})
        self.assertIn("one command in Linux", locked[0])

    def test_garbage_is_ignored(self):
        p = backend.parse_probe("disk\tonly-two\nhello\n\nreport\tOK\n")
        self.assertEqual(p["disks"], [])
        self.assertEqual(p["report"], [])


class Checks(unittest.TestCase):
    """The same rules as install.sh's valid_user, valid_hostname, valid_fullname."""

    def test_username(self):
        ok = ["alex", "a", "_svc", "a-b_c9", "abcdefghijklmnop"]
        bad = ["", "Alex", "9lives", "-x", "a b", "abcdefghijklmnopq", "é", "root", "operator"]
        for n in ok:
            self.assertEqual(backend.check_username(n), "", n)
        for n in bad:
            self.assertNotEqual(backend.check_username(n), "", n)

    def test_system_users_from_passwd(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("root:*:0:0::0:0:Charlie &:/root:/bin/sh\nmessagebus:*:556:556::0:0:D-BUS:/nonexistent:/usr/sbin/nologin\n"
                    "luna:*:1001:1001::0:0:Live user:/home/luna:/bin/sh\nnobody:*:65534:65534::0:0:Unprivileged:/nonexistent:/usr/sbin/nologin\n")
        try:
            reserved = backend.system_users(f.name)
        finally:
            os.unlink(f.name)
        self.assertEqual(reserved, {"root", "messagebus", "nobody"})
        self.assertNotEqual(backend.check_username("messagebus", reserved), "")
        # the live user's name is free on the installed system
        self.assertEqual(backend.check_username("luna", reserved), "")

    def test_hostname(self):
        for h in ["lunabsd", "alex-thinkpad", "a", "host.example.org", "A1"]:
            self.assertEqual(backend.check_hostname(h), "", h)
        for h in ["", "-x", "x-", "a b", "x_y", "a" * 65]:
            self.assertNotEqual(backend.check_hostname(h), "", h)

    def test_fullname(self):
        self.assertEqual(backend.check_fullname("Nguyễn Văn A"), "")
        for n in ["", "a:b", 'a"b', "a\\b", "a\nb"]:
            self.assertNotEqual(backend.check_fullname(n), "", repr(n))

    def test_install_sh_fullname_and_disk_contents(self):
        """install.sh's own valid_fullname refuses a newline (grep reads lines),
        and disk_contents does not count free space as a partition."""
        with open(os.path.join(REPO, "install.sh")) as f:
            text = f.read()
        fn = re.search(r"^valid_fullname\(\) \{.*?^\}", text, re.S | re.M).group(0)
        dc = re.search(r"^disk_contents\(\) \{.*?^\}", text, re.S | re.M).group(0)
        script = "NL='\n'\n" + fn + "\n" + dc + "\n" + \
            "gpart() { printf '%s\\n' '=>  40  100  da0  GPT  (1G)' '  40  2  -  free  -  (1K)' " \
            "'  42  50  da0p1  ms-basic-data  (25K)' '  92  48  -  free  -  (24K)'; }\n" + \
            'valid_fullname "$1" && echo ok || echo bad\ndisk_contents da0\n'
        for name, want in (("Alex Morgan", "ok"), ("a\nb", "bad"), ("a:b", "bad")):
            out = subprocess.run(["sh", "-c", script, "sh", name], capture_output=True, check=True).stdout.decode().split("\n")
            self.assertEqual(out[0], want, repr(name))
            self.assertEqual(out[1].strip(), "Windows/data (1)")

    def test_install_sh_swap_gives_way(self):
        """The size the installers offer starts at MIN_GB: install.sh's
        plan_sizes must not then refuse it because automatic swap took part
        of it. A chosen swap size is kept (and refused when it does not fit)."""
        with open(os.path.join(REPO, "install.sh")) as f:
            text = f.read()
        ps = re.search(r"^plan_sizes\(\) \{.*?^\}", text, re.S | re.M).group(0)
        script = ("die() { echo \"DIE: $*\"; exit 0; }\n"
                  "valid_number() { case \"$1\" in ''|*[!0-9]*) return 1 ;; esac; }\n"
                  "disk_secsize() { echo 512; }\nzpool() { return 1; }\n" + ps + "\n"
                  "INSTALL_MODE=alongside MIN_GB=30 FREE_START=2048 POOL=zroot\n"
                  "FREE_GB=$1 FREE_SECTORS=$(( $1 * 1073741824 / 512 )) ZFS_SIZE_GB=$2 HW_RAM_MB=$3 SWAP_SIZE=$4\n"
                  "plan_sizes; echo \"swap=$(( SWAP_SECTORS * 512 / 1048576 )) zfs=$ZFS_GB\"\n")

        def plan(free, asked, ram, swap="auto"):
            return subprocess.run(["sh", "-c", script, "sh", str(free), asked, str(ram), swap],
                                  capture_output=True, check=True).stdout.decode().strip()
        self.assertEqual(plan(30, "30", 16384), "swap=0 zfs=30")
        self.assertEqual(plan(34, "", 16384), "swap=4096 zfs=30")
        self.assertEqual(plan(100, "", 4096), "swap=4096 zfs=96")
        self.assertTrue(plan(30, "30", 16384, "4g").startswith("DIE:"))
        self.assertTrue(plan(29, "", 8192).startswith("DIE:"))

    def test_suggest_username(self):
        self.assertEqual(backend.suggest_username("Alex Morgan"), "alex")
        self.assertEqual(backend.suggest_username("  José  "), "jos")
        self.assertEqual(backend.suggest_username("42 Wallaby"), "u42")
        self.assertEqual(backend.check_username(backend.suggest_username("Alex Morgan")), "")

    def test_passwords(self):
        self.assertNotEqual(backend.check_password("", "", "password"), "")
        self.assertNotEqual(backend.check_password("a", "b", "password"), "")
        self.assertEqual(backend.check_password("x", "x", "password"), "")
        self.assertLess(backend.password_strength("abc"), backend.password_strength("Correct-Horse-9"))
        self.assertTrue(backend.is_ascii_printable("Pass word!"))
        self.assertFalse(backend.is_ascii_printable("pässword"))


def source_answers(text):
    """Source the answers file with a real sh, return the variables."""
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".conf") as f:
        f.write(text)
    try:
        script = '. "$1"; for k in %s; do eval "printf \'%%s\\0%%s\\0\' $k \\"\\$$k\\""; done' % " ".join(backend.ANSWER_KEYS)
        out = subprocess.run(["sh", "-c", script, "sh", f.name], capture_output=True, check=True).stdout.decode()
    finally:
        os.unlink(f.name)
    parts = out.split("\0")[:-1]
    return dict(zip(parts[0::2], parts[1::2]))


class Answers(unittest.TestCase):
    BASE = {
        "disk": "nda0", "mode": "alongside", "size_gb": 180, "fullname": "Alex Morgan",
        "username": "alex", "hostname": "alex-thinkpad", "password": "secret",
        "timezone": "Europe/Berlin", "language": "de", "layout": "de", "desktop": "kde",
        "terminal": "fish", "input_methods": [],
    }

    def test_roundtrip_through_sh(self):
        tricky = "it's \"$HOME\" `id` \\ $(reboot) ; & | * ?"
        a = dict(self.BASE, password=tricky, fullname="O'Brien Émile", encrypt=True, passphrase="p a$s")
        v = source_answers(backend.build_answers(a))
        self.assertEqual(v["USER_PASSWORD"], tricky)
        self.assertEqual(v["ROOT_PASSWORD"], tricky)          # same as the user's
        self.assertEqual(v["USER_FULLNAME"], "O'Brien Émile")
        self.assertEqual(v["ENCRYPT"], "yes")
        self.assertEqual(v["ENCRYPT_PASSPHRASE"], "p a$s")
        self.assertEqual(v["ZFS_SIZE_GB"], "180")
        self.assertEqual(v["INSTALL_MODE"], "alongside")
        self.assertEqual(v["BOOT_DEFAULT"], "keep")
        self.assertEqual(v["WIZ_LANG"], "de")
        self.assertEqual(v["INPUT_METHODS"], "none")
        self.assertEqual(v["RTC_LOCAL"], "auto")
        self.assertEqual(v["PKG_BRANCH"], "latest")       # the default: newest packages

    def test_erase_has_no_size_and_separate_root(self):
        a = dict(self.BASE, mode="erase", root_password="admin", boot_first=True,
                 input_methods=["vi", "bogus", "ja"], apps=False, gaming=True)
        v = source_answers(backend.build_answers(a))
        self.assertEqual(v["ZFS_SIZE_GB"], "")
        self.assertEqual(v["ROOT_PASSWORD"], "admin")
        self.assertEqual(v["BOOT_DEFAULT"], "freebsd")
        self.assertEqual(v["INPUT_METHODS"], "vi ja")
        self.assertEqual(v["INSTALL_APPS"], "no")
        self.assertEqual(v["INSTALL_GAMING"], "yes")
        self.assertEqual(v["ENCRYPT"], "no")
        self.assertEqual(v["ENCRYPT_PASSPHRASE"], "")

    def test_package_branch(self):
        v = source_answers(backend.build_answers(dict(self.BASE, pkg_branch="quarterly")))
        self.assertEqual(v["PKG_BRANCH"], "quarterly")
        # Hyprland needs latest whatever was chosen
        v = source_answers(backend.build_answers(dict(self.BASE, pkg_branch="quarterly", desktop="both")))
        self.assertEqual(v["PKG_BRANCH"], "latest")
        with self.assertRaises(ValueError):
            backend.build_answers(dict(self.BASE, pkg_branch="weekly"))

    def test_refuses_what_install_sh_refuses(self):
        for change in ({"disk": ""}, {"mode": ""}, {"username": "Root"}, {"hostname": "a b"},
                       {"password": ""}, {"encrypt": True, "passphrase": ""}, {"desktop": "gnome"},
                       {"fullname": "a:b"}):
            with self.assertRaises(ValueError, msg=str(change)):
                backend.build_answers(dict(self.BASE, **change))

    def test_every_key_is_written(self):
        text = backend.build_answers(self.BASE)
        for k in backend.ANSWER_KEYS:
            self.assertIn("\n%s=" % k, text)

    def test_secure_boot_answer(self):
        self.assertEqual(source_answers(backend.build_answers(self.BASE))["SECURE_BOOT"], "auto")
        self.assertEqual(source_answers(backend.build_answers(dict(self.BASE, secure_boot="off")))["SECURE_BOOT"], "off")
        with self.assertRaises(ValueError):
            backend.build_answers(dict(self.BASE, secure_boot="maybe"))
        # install.sh accepts exactly these (sb_decide)
        with open(os.path.join(REPO, "install.sh")) as f:
            body = f.read()
        self.assertIn('case "$SECURE_BOOT" in\n\tauto) ;;\n\toff)', body)


class SecureBootTest(unittest.TestCase):
    def test_probe_line(self):
        p = backend.parse_probe("secureboot\ton\tshim\t\n")
        self.assertEqual(p["secureboot"], {"state": "on", "plan": "shim", "why": ""})
        p = backend.parse_probe("secureboot\ton\tnone\tthis installer cannot sign the boot loader\n")
        self.assertEqual(p["secureboot"]["why"], "this installer cannot sign the boot loader")
        self.assertEqual(backend.parse_probe("")["secureboot"]["plan"], "none")

    def test_install_sh_prints_it(self):
        with open(os.path.join(REPO, "install.sh")) as f:
            body = f.read()
        self.assertIn("printf 'secureboot\\t%s\\t%s\\t%s\\n' \"$SB_STATE\" \"$SB_PLAN\"", body)

    def test_words(self):
        s = backend.secureboot_summary
        self.assertEqual(s({"state": "on", "plan": "shim"})["status"], "OK")
        self.assertIn("code", s({"state": "on", "plan": "shim"})["text"])
        self.assertIn("Setup Mode", s({"state": "setup", "plan": "own"})["short"])
        self.assertEqual(s({"state": "on", "plan": "none", "why": "x"})["status"], "NO")
        self.assertIn("secureboot enable", s({"state": "off", "plan": "none"})["text"])
        self.assertEqual(s({"state": "unsupported", "plan": "none"})["status"], "")

    def test_code_from_install_sh_message(self):
        text = demo.RESULT % backend.read_distro()
        self.assertEqual(backend.mok_code(backend.result_details(text, "LunaBSD")), "40718263")
        rest = backend.drop_mok(backend.result_details(text, "LunaBSD"))
        self.assertNotIn("40718263", rest)
        self.assertIn("firmware boot menu", rest)
        self.assertEqual(backend.mok_code("nothing here"), "")
        # the demo text is what install.sh writes
        with open(os.path.join(REPO, "install.sh")) as f:
            body = f.read()
        self.assertIn("Enroll MOK, then Continue, then Yes, type this code and press Enter:", body)


class ProgressTest(unittest.TestCase):
    def test_monotonic_and_complete(self):
        p = backend.Progress()
        last = 0.0
        titles = set()
        for line in demo.install_lines():
            p.feed(line)
            self.assertGreaterEqual(p.fraction, last, line)
            last = p.fraction
            titles.add(p.title)
        self.assertGreater(p.fraction, 0.97)
        self.assertIn("Installing KDE Plasma (the longest part)", titles)
        self.assertIn("Downloading and installing the base system", titles)

    def test_install_sh_lines(self):
        p = backend.Progress()
        p.feed("\n==== Installing the desktop (the long part) ====")
        start = p.fraction
        p.feed("==== kde ====")
        k = p.fraction
        p.feed("       [100/400] Fetching plasma6-kwin-6.8.3.pkg: .......... done")
        mid = p.fraction
        p.feed("       [400/400] Installing qt6-base-6.11.3...")
        self.assertLess(start, k)
        self.assertLess(k, mid)
        self.assertLess(mid, p.fraction)
        self.assertEqual(p.detail, "Installing qt6-base-6.11.3")
        p.feed("WARNING: something odd")      # unknown lines change nothing
        self.assertEqual(p.title, "Installing KDE Plasma (the longest part)")

    def test_stage_names_match_setup_sh(self):
        with open(os.path.join(backend.REPO, "setup.sh")) as f:
            line = next(l for l in f if l.startswith("STAGES="))
        stages = line.split('"')[1].split()
        self.assertEqual([s for s, _ in backend.STAGES], stages)


class Tables(unittest.TestCase):
    def test_wizard_tables(self):
        langs, layouts = backend.read_wizard_tables()
        self.assertIn("vi", [l["code"] for l in langs])
        self.assertIn("de", [l["xkb"] for l in layouts])
        for lang, lay in backend.LANG_LAYOUTS.items():
            self.assertIn(lay, [l["xkb"] for l in layouts], lang)
        for lang in backend.LANG_ZONES:
            self.assertIn(lang, [l["code"] for l in langs])

    def test_distro(self):
        d = backend.read_distro()
        self.assertEqual(d["DISTRO_NAME"], "LunaBSD")
        self.assertTrue(d["FREEBSD_RELEASE"].startswith("15."))

    def test_result_details(self):
        text = demo.RESULT % backend.read_distro()
        out = backend.result_details(text, "LunaBSD")
        self.assertFalse(out.startswith("LunaBSD is installed"))
        self.assertIn("firmware boot menu", out)
        self.assertEqual(backend.result_details("LunaBSD is installed.\n\nRemove the USB stick and restart the computer.", "LunaBSD"), "")


if __name__ == "__main__":
    unittest.main(verbosity=1)
