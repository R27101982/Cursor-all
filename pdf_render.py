"""Печать HTML в PDF через headless Chrome."""

import subprocess
import tempfile
import time
from pathlib import Path


def render(html_path: Path, pdf_path: Path, timeout: float = 90) -> None:
    """Chrome печатает PDF почти сразу, но сам не всегда завершается,
    поэтому ждём появления готового файла и гасим процесс вручную."""

    pdf_path.unlink(missing_ok=True)

    with tempfile.TemporaryDirectory() as profile:
        proc = subprocess.Popen(
            [
                "google-chrome",
                "--headless",
                "--no-sandbox",
                "--disable-gpu",
                f"--user-data-dir={profile}",
                "--no-pdf-header-footer",
                f"--print-to-pdf={pdf_path}",
                html_path.as_uri(),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        deadline = time.time() + timeout
        last_size = -1
        try:
            while time.time() < deadline:
                if proc.poll() is not None:
                    break
                size = pdf_path.stat().st_size if pdf_path.exists() else 0
                if size and size == last_size:
                    break
                last_size = size
                time.sleep(0.5)
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()

    if not pdf_path.exists() or pdf_path.stat().st_size == 0:
        raise SystemExit(f"Chrome не создал {pdf_path.name}")

    print(f"PDF: {pdf_path.name} ({pdf_path.stat().st_size // 1024} KB)")
