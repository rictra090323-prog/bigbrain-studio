# Python för BigBrains lokala bygge

Hämta [Astrals Python 3.12.16 för Apple-chip](https://github.com/astral-sh/python-build-standalone/releases/download/20261026/cpython-3.12.16%2B20261026-aarch64-apple-darwin-install_only_stripped.tar.gz). Låt filen vara komprimerad och spara den i den här mappen som `python-3.12.16-arm64.tar.gz`. Om webbläsaren packar upp filen automatiskt kan du hämta den med kommandot nedan från projektets rotmapp.

```sh
curl --fail --location \
  --output Dependencies/python-3.12.16-arm64.tar.gz \
  'https://github.com/astral-sh/python-build-standalone/releases/download/20261026/cpython-3.12.16%2B20261026-aarch64-apple-darwin-install_only_stripped.tar.gz'
```

Byggsteget verifierar att SHA-256 är `353d5f1b4fd2715e7053f12f068435d5bbad16b91e057006b5d01e0925709a7e` före uppackning.
