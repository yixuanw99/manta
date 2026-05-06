> **This is a patched fork of Manta v1.6.0.**
> See [Patch Notes](#patch-notes) and [Build Instructions](#building-the-patched-binary) below.

---

Patch Notes
-----------

### Change: `MAX_QSCORE` raised from 70 to 93

**File:** `src/c++/lib/blt_util/qscore_cache.hpp`

**Original line:**
```cpp
enum { MAX_QSCORE = 70, MAX_MAP = 90 };
```

**Patched line:**
```cpp
enum { MAX_QSCORE = 93, MAX_MAP = 90 };
```

**Reason:**  
cfDNA consensus reads produced by [fgbio](http://fulcrumgenomics.github.io/fgbio/)
`CallMolecularConsensusReads` can carry base quality (BQ) scores higher than 70.
Stock Manta 1.6.0 hard-codes `MAX_QSCORE = 70` and aborts with a fatal error
(`high_qscore_error`) whenever it encounters a read with BQ > 70.  
Raising the limit to 93 (the maximum value representable in a Phred+33 encoded
FASTQ/BAM) allows Manta to process these BAMs without prior quality-capping.

**Impact:** Read-level BQ values are clamped at the cache boundary; changing the
limit does not alter the SV-calling algorithm or scoring logic.

---

Building the Patched Binary
---------------------------

### 1. Prerequisites

- Linux x86-64
- [Conda / Mamba](https://conda-forge.org/miniforge/)

### 2. Create the build environment

```bash
conda env create -f build-env.yaml
# creates the conda env "manta_build_py2"
```

**Why a dedicated env?**  
Manta's build system has several hard requirements that conflict with modern
toolchain defaults:

| Requirement | Reason |
|---|---|
| **Python 2.7** | `CMakeLists.txt` calls `find_package(PythonInterp 2)` and all workflow scripts are Python 2. |
| **CMake ≤ 3.x** | CMake ≥ 4.0 removed `FindBoost` and `FindPythonInterp`, which this project depends on. Tested with `cmake=3.31.8`. |
| **GCC/G++ 11.x** | GCC ≥ 15 breaks the bundled Boost 1.58 bootstrap. |
| **No conda Boost** | Manta bootstraps Boost 1.58 from a bundled tarball. Installing `boost-cpp` into the build env causes a header/library version mismatch ("Boost.Math requires C++14"). Do not add boost to `build-env.yaml`. |

### 3. Build and install

```bash
conda activate manta_build_py2
bash build-patched.sh [--install-dir ./install] [--jobs 4]
```

Default install location: `./install/` (relative to repo root).

### 4. Binaries produced

All five C++ executables share the same internal serialization format for
`svLocusGraph.bin`. You **must replace all five** together when deploying;
replacing only a subset causes a fatal "unsupported version" deserialization
error at runtime.

```
install/libexec/EstimateSVLoci
install/libexec/MergeSVLoci
install/libexec/CheckSVLoci
install/libexec/SummarizeSVLoci
install/libexec/GenerateSVCandidates
```

### 5. Deploying into a Docker image (recommended)

The binaries are statically linked (`-static-libgcc -static-libstdc++`) and
have no extra runtime dependencies. Copy them directly into the conda Manta
install without rebuilding inside Docker:

```dockerfile
# Copy all five patched binaries over the conda-installed stock ones.
# The Python workflow scripts (configManta.py etc.) remain untouched.
COPY resources/bin/manta-patched/ /opt/conda/envs/sv_tools/libexec/
```

---

Manta Structural Variant Caller
===============================

Manta calls structural variants (SVs) and indels from mapped
paired-end sequencing reads. It is optimized for analysis of germline
variation in small sets of individuals and somatic variation in
tumor/normal sample pairs. Manta discovers, assembles and scores
large-scale SVs, medium-sized indels and large insertions within a
single efficient workflow. The method is designed for rapid analysis
on standard compute hardware: NA12878 at 50x genomic coverage is
analyzed in less than 20 minutes on a 20 core server, and most WGS
tumor/normal analyses can be completed within 2 hours. Manta combines
paired and split-read evidence during SV discovery and scoring to
improve accuracy, but does not require split-reads or successful
breakpoint assemblies to report a variant in cases where there is
strong evidence otherwise. It provides scoring models for germline
variants in small sets of diploid samples and somatic variants in
matched tumor/normal sample pairs. There is experimental support for
analysis of unmatched tumor samples as well. Manta accepts input read
mappings from BAM or CRAM files and reports all SV and indel inferences
in VCF 4.1 format. See the [user guide][UserGuide] for a full
description of capabilities and limitations.

[UserGuide]:docs/userGuide/README.md

Methods and benchmarking details are described in:

Chen, X. *et al.* (2016) Manta: rapid detection of structural variants and
indels for germline and cancer sequencing applications. *Bioinformatics*,
32, 1220-1222. [doi:10.1093/bioinformatics/btv710][bpaper]

...and the corresponding [open-access pre-print][preprint].

[bpaper]:https://doi.org/10.1093/bioinformatics/btv710
[preprint]:https://doi.org/10.1101/024232


License
-------

Manta source code is provided under the [Polyform strict license](LICENSE.txt).
Manta includes several third party packages provided under other
open source licenses, please see [COPYRIGHT.txt](COPYRIGHT.txt)
for additional details.


Getting Started
---------------

For linux users, it is recommended to start from the most recent
[binary distribution on the Manta releases page][releases], this
distribution can be unpacked, moved to any convenient directory and
tested by [running a small demo](docs/userGuide/installation.md#demo)
included with the release distribution. Manta can also be installed
and run on OS X. Please see the [installation instructions](docs/userGuide/installation.md)
for full build and installation details of all supported cases.

[releases]:https://github.com/Illumina/manta/releases


Data Analysis and Interpretation
--------------------------------

After completing installation, see the [Manta user guide][UserGuide]
for instructions on how to run Manta, interpret results and estimate
hardware requirements/compute cost, in addition to a high-level methods
overview.


Manta Code Development
----------------------

For manta code development and debugging details, see the
[Manta developer guide][DeveloperGuide]. This includes details
on Manta's developement protocols, special build instructions,
recommended workflows for investigating
calls, and internal documentation details.

[DeveloperGuide]:docs/developerGuide/README.md
