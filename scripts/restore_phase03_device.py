"""Restore this run's phone backup after installing the verified normal APK.

Run only with the target phone connected and unlocked. A nonempty database is
never overwritten. Backup contents and model credentials are not printed.
"""
import hashlib
import pathlib
import sqlite3
import subprocess
import tarfile
from datetime import datetime

ADB = r"D:\Android\Sdk\platform-tools\adb.exe"
DEVICE = "3B15A600NHN00000"
PACKAGE = "com.example.pxt1"
ROOT = pathlib.Path(__file__).resolve().parents[1]
APK = ROOT / "build/app/outputs/flutter-apk/app-debug.apk"
BACKUP_ROOT = pathlib.Path(r"C:\Users\28304\AppData\Local\pxt-backups\20261013-155225")
BACKUP = BACKUP_ROOT / "app-private-data.tar"
APK_HASH = "84F28C34B5555B45B7667187EC2AC7E6231F6FB5E228B968FC2DC61381606411"


def adb(*args, **kwargs):
    return subprocess.run([ADB, "-s", DEVICE, *args], check=True, **kwargs)


def main():
    if hashlib.sha256(APK.read_bytes()).hexdigest().upper() != APK_HASH:
        raise RuntimeError("APK differs from the verified normal build; stop.")
    with tarfile.open(BACKUP) as archive:
        if not any(m.name.endswith("/databases/paixuetong.db") for m in archive.getmembers()):
            raise RuntimeError("Original backup has no database; stop.")
    adb("get-state", capture_output=True)
    adb("install", "-r", str(APK))
    adb("shell", "am", "force-stop", PACKAGE)
    checkpoint = BACKUP_ROOT / ("before-final-restore-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    checkpoint.mkdir()
    with (checkpoint / "current-data.tar").open("wb") as output:
        adb("exec-out", "run-as", PACKAGE, "tar", "-cf", "-", ".", stdout=output)
    with tarfile.open(checkpoint / "current-data.tar") as archive:
        for member in archive.getmembers():
            if member.name.startswith("./databases/"):
                archive.extract(member, checkpoint, filter="data")
    database = checkpoint / "databases/paixuetong.db"
    nonempty = False
    if database.exists():
        with sqlite3.connect(database) as connection:
            nonempty = connection.execute("SELECT COUNT(*) FROM users").fetchone()[0] > 0
    if nonempty:
        print("Existing user data found: preserved without overwriting. Verify manually.")
    else:
        adb("push", str(BACKUP), "/data/local/tmp/pxt-private-restore.tar")
        adb("shell", "run-as", PACKAGE, "tar", "-xf", "/data/local/tmp/pxt-private-restore.tar")
        print("Original private data restored, including all source files and configuration.")
    adb("shell", "rm", "-f", "/data/local/tmp/pxt-private-restore.tar")
    restored = checkpoint / "restored.db"
    with restored.open("wb") as output:
        adb("exec-out", "run-as", PACKAGE, "cat", "databases/paixuetong.db", stdout=output)
    with sqlite3.connect(restored) as connection:
        print("integrity:", connection.execute("PRAGMA integrity_check").fetchone()[0])
        for table in ["source_documents", "practice_questions", "knowledge_libraries", "learning_resources"]:
            print(table, connection.execute("SELECT COUNT(*) FROM " + table).fetchone()[0])
    adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
    print("Normal app launched. Current-data checkpoint:", checkpoint)


if __name__ == "__main__":
    main()
