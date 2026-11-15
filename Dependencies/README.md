# Python runtime for local builds

Download [Astral’s Python 3.12.16 for Apple silicon](https://github.com/astral-sh/python-build-standalone/releases/download/20261026/cpython-3.12.16%2B20261026-aarch64-apple-darwin-install_only_stripped.tar.gz). Keep the file compressed and save it in this directory as `python-3.12.16-arm64.tar.gz`. If your browser extracts it automatically, run the command below from the project root.

```sh
curl --fail --location \
  --output Dependencies/python-3.12.16-arm64.tar.gz \
  'https://github.com/astral-sh/python-build-standalone/releases/download/20261026/cpython-3.12.16%2B20261026-aarch64-apple-darwin-install_only_stripped.tar.gz'
```

The build verifies the SHA-256 checksum `353d5f1b4fd2715e7053f12f068435d5bbad16b91e057006b5d01e0925709a7e` before extracting the archive.
