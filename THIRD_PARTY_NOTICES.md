# Third-party notices

Safe Location's UI and app-level orchestration are provided in this package. The low-level on-device DVT / Remote Pairing FFI dependency is downloaded at build time from a pinned revision of:

- Locus: https://github.com/ChrisMack32/Locus
- Pinned tree/commit reference used by this package: `83c8fb324983728e8f44759cfd834dc637ee38b5`
- Files downloaded by `Scripts/bootstrap_vendor.sh`:
  - `Vendor/idevice/idevice.h`
  - `Vendor/idevice/libidevice_ffi.a`
  - `Vendor/idevice/module.modulemap`

Locus states that its `Vendor/idevice` integration is MIT-licensed and is based on the `idevice` project.

## Locus MIT License

MIT License

Copyright (c) 2026 Locus contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
